variable "project_name" {
  type    = string
  default = "listmonk2"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "owner" {
  type    = string
  default = "devops-team"
}

variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "postgres_engine_version" {
  type    = string
  default = "16.4"
}

variable "postgres_major_family" {
  type    = string
  default = "16"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_name" {
  type    = string
  default = "listmonk"
}

variable "db_username" {
  type    = string
  default = "listmonk"
}

variable "listmonk_admin_user" {
  type    = string
  default = "admin"
}

# GitHub: "org/repo" (sin https)
variable "github_repo_url" {
  type = string
}

# Para restringir acceso al panel (si configuras Ingress auth/IP)
variable "allowed_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
