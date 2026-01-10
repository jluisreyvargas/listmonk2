terraform {
  required_version = ">= 1.14.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.27"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # Backend: rellena backend.tf (ver backend.tf.example)
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project      = var.project_name
      Environment  = var.environment
      Owner        = var.owner
      ManagedBy    = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "${var.project_name}-${var.environment}"
  tags = {
    Project      = var.project_name
    Environment  = var.environment
    Owner        = var.owner
    ManagedBy    = "terraform"
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.5.1"

  name = local.name
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets  = [for i, az in slice(data.aws_availability_zones.available.names, 0, 3) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets   = [for i, az in slice(data.aws_availability_zones.available.names, 0, 3) : cidrsubnet(var.vpc_cidr, 8, 48 + i)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

resource "aws_ecr_repository" "listmonk" {
  name                 = "${local.name}-listmonk"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.tags
}

resource "random_password" "db" {
  length  = 32
  special = true
}

resource "aws_security_group" "db" {
  name_prefix = "${local.name}-db-"
  description = "DB SG"
  vpc_id      = module.vpc.vpc_id
  tags        = local.tags
}

module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "7.0.0"

  identifier = "${local.name}-postgres"

  engine               = "postgres"
  engine_version       = var.postgres_engine_version
  family               = "postgres${var.postgres_major_family}"
  major_engine_version = var.postgres_major_family

  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result
  port     = 5432

  create_db_subnet_group = true
  subnet_ids             = module.vpc.private_subnets

  vpc_security_group_ids = [aws_security_group.db.id]

  deletion_protection = false
  skip_final_snapshot = true

  tags = local.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.11.0"

  cluster_name    = local.name
  cluster_version = "1.34"

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      min_size       = 2
      max_size       = 4
      desired_size   = 2

      ami_type = "AL2023_x86_64_STANDARD"
    }
  }

  tags = local.tags
}

resource "aws_security_group_rule" "db_from_eks_nodes" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = module.eks.node_security_group_id
  description              = "Postgres from EKS nodes"
}

resource "aws_secretsmanager_secret" "listmonk" {
  name        = "${local.name}/listmonk"
  description = "Listmonk app secrets (DB + admin). Synced to K8s via External Secrets."
  tags        = local.tags
}

resource "random_password" "admin" {
  length  = 20
  special = false
}

resource "aws_secretsmanager_secret_version" "listmonk" {
  secret_id = aws_secretsmanager_secret.listmonk.id
  secret_string = jsonencode({
    DB_HOST = module.db.db_instance_address
    DB_PORT = "5432"
    DB_NAME = var.db_name
    DB_USER = var.db_username
    DB_PASSWORD = random_password.db.result

    LISTMONK_ADMIN_USER = var.listmonk_admin_user
    LISTMONK_ADMIN_PASSWORD = random_password.admin.result
  })
}

# --- IRSA roles for controllers (External Secrets + AWS LB Controller) ---
data "aws_iam_policy_document" "external_secrets_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider, "https://", "")}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets"]
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "${local.name}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_assume.json
  tags               = local.tags
}

resource "aws_iam_policy" "external_secrets" {
  name        = "${local.name}-external-secrets"
  description = "Allow External Secrets to read Secrets Manager secrets"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [aws_secretsmanager_secret.listmonk.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets.arn
}

data "http" "alb_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.17.0/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "aws_lb_controller" {
  name        = "${local.name}-aws-lb-controller"
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = data.http.alb_iam_policy.response_body
}

data "aws_iam_policy_document" "aws_lb_controller_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "aws_lb_controller" {
  name               = "${local.name}-aws-lb-controller"
  assume_role_policy = data.aws_iam_policy_document.aws_lb_controller_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "aws_lb_controller" {
  role       = aws_iam_role.aws_lb_controller.name
  policy_arn = aws_iam_policy.aws_lb_controller.arn
}

# --- GitHub OIDC role to push images to ECR ---
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # Thumbprint puede cambiar; si falla, actualiza con la recomendación oficial de GitHub.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  tags            = local.tags
}

data "aws_iam_policy_document" "github_actions_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo_url}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${local.name}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume.json
  tags               = local.tags
}

resource "aws_iam_policy" "github_actions" {
  name        = "${local.name}-github-actions"
  description = "Allow GitHub Actions to push to ECR"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["ecr:GetAuthorizationToken"],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories"
        ],
        Resource = aws_ecr_repository.listmonk.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions.arn
}

output "cluster_name" { value = module.eks.cluster_name }
output "region" { value = var.aws_region }
output "ecr_repository_url" { value = aws_ecr_repository.listmonk.repository_url }
output "secrets_manager_secret_name" { value = aws_secretsmanager_secret.listmonk.name }
output "db_endpoint" { value = module.db.db_instance_endpoint }
output "github_oidc_role_arn" { value = aws_iam_role.github_actions.arn }
