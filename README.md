# Proyecto ListMonk2 (AWS + Terraform + EKS + ArgoCD GitOps + Blue/Green)

Este repo es **replicable** y contiene todo lo necesario para desplegar Listmonk en AWS cumpliendo:
- IaC con **Terraform**
- Contenedores con **Docker**
- Orquestación con **Kubernetes (EKS)**
- **GitOps** con **Argo CD** (sync automático)
- Estrategia **Blue/Green** con **Argo Rollouts**
- Observabilidad: **métricas, logs y alertas**
- Seguridad (GitOps track): **secretos** con **External Secrets** + AWS Secrets Manager (sin secretos en Git), **IRSA**, **pods non-root**

## Versiones usadas (enero 2026)
Consulta `VERSIONS.json`. Principales:
- Terraform 1.14.3
- AWS provider 6.27.0
- terraform-aws-modules/eks 21.11.0
- EKS Kubernetes 1.34
- Argo CD v3.2.3 (chart 9.2.4)
- Argo Rollouts v1.8.3 (chart 2.40.5)
- External Secrets v1.2.1
- kube-prometheus-stack 80.11.0
- AWS Load Balancer Controller v2.17.0
- listmonk v6.0.0

---

# 0) Prerrequisitos (local)
1. AWS CLI v2 configurado (`aws configure`) con una cuenta con permisos de admin para laboratorio.
2. kubectl compatible con Kubernetes 1.34.
3. Helm 3.
4. Terraform 1.14.3.
5. Git.
6. Docker.
7. Opcional recomendado: `jq`.

> Nota: **No** hay secretos en este repo. Todo sale de AWS Secrets Manager vía External Secrets.

---

# 1) Estructura del repositorio
- `app/` → código Docker para construir imagen de listmonk (desde el tag v6.0.0)
- `infra/terraform/` → VPC, EKS, ECR, RDS PostgreSQL, Secrets Manager, IAM/IRSA, S3 backend
- `gitops/` → todo lo que Argo CD aplica al clúster (apps + helm + manifests)
- `.github/workflows/` → CI/CD (build/test/scan + push a ECR + PR a gitops)

---

# 2) Configuración rápida (valores que debes cambiar)
Edita `infra/terraform/envs/dev/terraform.tfvars` y ajusta como mínimo:
- `project_name` (default: listmonk2)
- `aws_region`
- `domain_name` (si quieres Ingress con DNS; si no, puedes entrar por el ALB URL)
- `github_repo_url` (URL de tu repo)
- `allowed_cidrs` (tu IP o rango para acceso admin)

---

# 3) Backend de Terraform (S3 + DynamoDB)
Este repo incluye `infra/terraform/bootstrap/` para crear:
- bucket S3 para state
- tabla DynamoDB para lock
- KMS key para cifrado (opcional pero recomendado)

## 3.1 Crear backend
```bash
cd infra/terraform/bootstrap
terraform init
terraform apply -auto-approve
```

Anota los outputs (bucket, dynamodb table) y ya puedes usar el entorno.

---

# 4) Desplegar infraestructura (EKS + RDS + ECR + addons base)
```bash
cd ../envs/dev
terraform init
terraform apply -auto-approve
```

Al terminar, Terraform imprime:
- nombre del cluster EKS
- URL del repositorio ECR
- endpoint/DB name de RDS
- nombre del Secret de AWS Secrets Manager

---

# 5) Configurar kubectl para EKS
```bash
aws eks update-kubeconfig --region <REGION> --name <CLUSTER_NAME>
kubectl get nodes
```

---

# 6) Bootstrap GitOps (Argo CD + Apps)
Hay 2 formas. Para proyecto, la más simple:

## 6.1 Instalar Argo CD (una sola vez, bootstrap)
```bash
kubectl create namespace argocd || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.2.3/manifests/install.yaml
```

Espera a que esté listo:
```bash
kubectl -n argocd rollout status deploy/argocd-server
```

## 6.2 Aplicar el "App of Apps"
Edita en `gitops/argocd/root-app.yaml` el repo/branch si es necesario, y aplica:
```bash
kubectl apply -n argocd -f gitops/argocd/root-app.yaml
```

Desde aquí ArgoCD instala automáticamente:
- aws-load-balancer-controller
- external-secrets
- argo-rollouts
- kube-prometheus-stack (métricas/alertas)
- loki (logs)
- listmonk (blue/green)

---

# 7) Secretos (AWS Secrets Manager -> External Secrets)
Terraform crea en Secrets Manager un secret JSON con:
- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`
- `LISTMONK_ADMIN_USER`, `LISTMONK_ADMIN_PASSWORD`

External Secrets sincroniza eso a un Secret de Kubernetes en el namespace `listmonk`.

Validación:
```bash
kubectl -n listmonk get externalsecret,secret
```

---

# 8) Blue/Green (Argo Rollouts)
Listmonk se despliega como un `Rollout`:
- service **listmonk-active** (tráfico real)
- service **listmonk-preview** (pre-visualización)

Para probar:
```bash
kubectl -n listmonk argo rollouts get rollout listmonk
kubectl -n listmonk argo rollouts promote listmonk
```

---

# 9) CI/CD (GitHub Actions)
Workflows:
- `ci.yml` → lint + tests + build + trivy + push a ECR (sin usar tags `latest`)
- `update-gitops.yml` → crea PR actualizando el `kustomization.yaml` con la nueva tag (GitOps)

Necesitas:
1. Crear un **IAM role** para GitHub OIDC (Terraform lo crea) y configurar en GitHub:
   - `AWS_ROLE_TO_ASSUME`
   - `AWS_REGION`
2. Configurar `ECR_REPOSITORY` (output de Terraform)

---

# 10) Observabilidad
- **Prometheus/Grafana/Alertmanager** vía kube-prometheus-stack
- **Loki** para logs

Acceso rápido (port-forward):
```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

---

# 11) Tags AWS
Terraform usa `default_tags` en el provider, así **todos los recursos** llevan:
- `Project = <project_name>`
- `Environment = <env>`
- `Owner = <owner>`
- `ManagedBy = terraform`

---

# 12) Destrucción
```bash
cd infra/terraform/envs/dev
terraform destroy -auto-approve
```

---

## Notas de seguridad (anti-patterns evitados)
- ❌ No hay secretos en Git.
- ✅ Pods non-root + readOnlyRootFilesystem en la app.
- ✅ IRSA para controllers (AWS LB controller y external-secrets).
