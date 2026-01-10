#!/usr/bin/env bash
set -euo pipefail

# Ejecuta desde la raíz del repo.
# Requiere: terraform output -json en infra/terraform/envs/dev

ENV_DIR="infra/terraform/envs/dev"

pushd "$ENV_DIR" >/dev/null
OUT="$(terraform output -json)"
popd >/dev/null

cluster_name="$(echo "$OUT" | jq -r .cluster_name.value)"
region="$(echo "$OUT" | jq -r .region.value)"
ecr_repo="$(echo "$OUT" | jq -r .ecr_repository_url.value)"
secret_name="$(echo "$OUT" | jq -r .secrets_manager_secret_name.value)"
alb_role_arn="$(terraform -chdir=$ENV_DIR state show aws_iam_role.aws_lb_controller | awk '/arn/{print $3; exit}')"
eso_role_arn="$(terraform -chdir=$ENV_DIR state show aws_iam_role.external_secrets | awk '/arn/{print $3; exit}')"
vpc_id="$(terraform -chdir=$ENV_DIR state show module.vpc.aws_vpc.this[0] | awk '/id =/{print $3; exit}')"

echo "cluster_name=$cluster_name"
echo "region=$region"
echo "ecr_repo=$ecr_repo"
echo "secret_name=$secret_name"

# root-app repoURL: usa tu URL https://github.com/<org>/<repo>.git
if [[ -z "${GIT_REPO_URL:-}" ]]; then
  echo "ERROR: export GIT_REPO_URL=https://github.com/<org>/<repo>.git"
  exit 1
fi

# Reemplazos
files=(
  gitops/argocd/root-app.yaml
  gitops/apps/aws-load-balancer-controller.yaml
  gitops/apps/external-secrets.yaml
  gitops/apps/argo-rollouts.yaml
  gitops/apps/kube-prometheus-stack.yaml
  gitops/apps/aws-for-fluent-bit.yaml
  gitops/apps/listmonk.yaml
  gitops/platform/external-secrets/clustersecretstore.yaml
  gitops/values/aws-load-balancer-controller-values.yaml
  gitops/values/aws-for-fluent-bit-values.yaml
  gitops/workloads/listmonk/externalsecret.yaml
  gitops/workloads/listmonk/configmap.yaml
  gitops/workloads/listmonk/ingress.yaml
  gitops/workloads/listmonk/kustomization.yaml
)

for f in "${files[@]}"; do
  sed -i "s|REPLACE_ME_REPO_URL|$GIT_REPO_URL|g" "$f"
  sed -i "s|REPLACE_ME_CLUSTER_NAME|$cluster_name|g" "$f"
  sed -i "s|REPLACE_ME_AWS_REGION|$region|g" "$f"
  sed -i "s|REPLACE_ME_SECRETS_MANAGER_NAME|$secret_name|g" "$f"
  sed -i "s|REPLACE_ME_AWS_LB_CONTROLLER_ROLE_ARN|$alb_role_arn|g" "$f"
  sed -i "s|REPLACE_ME_EXTERNAL_SECRETS_ROLE_ARN|$eso_role_arn|g" "$f"
  sed -i "s|REPLACE_ME_VPC_ID|$vpc_id|g" "$f"
  # Image placeholders
  sed -i "s|REPLACE_ME_IMAGE:REPLACE_ME_TAG|$ecr_repo:$cluster_name|g" "$f" || true
done

# Imagen en kustomization: newName/newTag
sed -i "s|name: REPLACE_ME_IMAGE|name: $ecr_repo|g" gitops/workloads/listmonk/kustomization.yaml
sed -i "s|newName: REPLACE_ME_IMAGE|newName: $ecr_repo|g" gitops/workloads/listmonk/kustomization.yaml
sed -i "s|newTag: REPLACE_ME_TAG|newTag: initial|g" gitops/workloads/listmonk/kustomization.yaml

echo "OK: placeholders renderizados. Revisa HOST/ROOT_URL manualmente."
