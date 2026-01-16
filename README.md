
# Proyecto ListMonk2 (AWS + Terraform + EKS + ArgoCD GitOps + Blue/Green)

Este repositorio es **replicable** y contiene todo lo necesario para desplegar **Listmonk** en AWS cumpliendo con prácticas modernas de plataforma y DevOps:

- **IaC** con **Terraform**
- Contenedores con **Docker**
- Orquestación con **Kubernetes (EKS)**
- **GitOps** con **Argo CD** (sincronización automática)
- Estrategia **Blue/Green** con **Argo Rollouts**
- Observabilidad: **métricas, logs y alertas**
- Seguridad:
  - **External Secrets** + **AWS Secrets Manager** (sin secretos en Git)
  - **IRSA**
  - **pods non-root** y filesystem de solo lectura
  - Escaneo de imágenes con **Trivy** en CI

---

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

## 0) Prerrequisitos (local)

1. AWS CLI v2 configurado (`aws configure`) con una cuenta con permisos de admin (entorno laboratorio).
2. kubectl compatible con Kubernetes 1.34.
3. Helm 3.
4. Terraform 1.14.3.
5. Git.
6. Docker.
7. Opcional recomendado: `jq`.

> Nota: **No hay secretos en este repositorio**. Todo se obtiene desde AWS Secrets Manager vía External Secrets.

---

## 1) Estructura del repositorio

- `app/` → Dockerfile y scripts para construir la imagen de Listmonk (basada en v6.0.0)
- `infra/terraform/` → VPC, EKS, RDS PostgreSQL, Secrets Manager, IAM/IRSA, backend S3
- `gitops/` → Manifiestos y aplicaciones que Argo CD aplica al clúster
- `.github/workflows/` → CI/CD (build + test + scan + push + PR GitOps)

---

## 2) Configuración rápida (valores que debes cambiar)

Edita `infra/terraform/envs/dev/terraform.tfvars` y ajusta como mínimo:

- `project_name` (default: `listmonk2`)
- `aws_region`
- `domain_name` (opcional; si no se define se accede vía URL del ALB)
- `github_repo_url`
- `allowed_cidrs` (IP/rango para acceso administrativo)

---

## 3) Backend de Terraform (S3 + DynamoDB)

Este repo incluye `infra/terraform/bootstrap/` para crear:

- Bucket S3 para el state
- Tabla DynamoDB para locking
- KMS key para cifrado (opcional pero recomendado)

### 3.1 Crear backend

```bash
cd infra/terraform/bootstrap
terraform init
terraform apply -auto-approve
```

Guarda los outputs (bucket y tabla DynamoDB).

---

## 4) Desplegar infraestructura (EKS + RDS + addons base)

```bash
cd ../envs/dev
terraform init
terraform apply -auto-approve
```

Terraform imprime:

- Nombre del cluster EKS
- Endpoint y nombre de la base de datos RDS
- Nombre del Secret en AWS Secrets Manager

---

## 5) Configurar kubectl para EKS

```bash
aws eks update-kubeconfig --region <REGION> --name <CLUSTER_NAME>
kubectl get nodes
```

---

## 6) Bootstrap GitOps (Argo CD)

### 6.1 Instalar Argo CD (una sola vez)

```bash
kubectl create namespace argocd || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.2.3/manifests/install.yaml
```

Esperar a que esté listo:

```bash
kubectl -n argocd rollout status deploy/argocd-server
```

### 6.2 Aplicar el patrón "App of Apps"

Edita `gitops/argocd/root-app.yaml` si es necesario y aplica:

```bash
kubectl apply -n argocd -f gitops/argocd/root-app.yaml
```

Desde aquí Argo CD instala automáticamente:

- aws-load-balancer-controller
- external-secrets
- argo-rollouts
- kube-prometheus-stack (métricas y alertas)
- loki (logs)
- listmonk (estrategia Blue/Green)

---

## 7) Secretos (AWS Secrets Manager → External Secrets)

Terraform crea un secret JSON en AWS Secrets Manager con:

- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`
- `LISTMONK_ADMIN_USER`, `LISTMONK_ADMIN_PASSWORD`

External Secrets sincroniza este secret a Kubernetes en el namespace `listmonk`.

Validación:

```bash
kubectl -n listmonk get externalsecret,secret
```

---

## 8) Blue/Green (Argo Rollouts)

Listmonk se despliega como un `Rollout`:

- Service **listmonk-active** → tráfico real
- Service **listmonk-preview** → previsualización

Comandos útiles:

```bash
kubectl -n listmonk argo rollouts get rollout listmonk
kubectl -n listmonk argo rollouts promote listmonk
```

---

## 9) CI/CD (GitHub Actions + GitOps)

El pipeline de CI/CD se basa en **GitHub Actions** y sigue un flujo GitOps completo.

### Workflows

- `ci.yml`
  - Ejecuta tests upstream
  - Construye la imagen Docker
  - Escanea la imagen con **Trivy** (bloqueante para CRITICAL y HIGH)
  - Publica la imagen en **GitHub Container Registry (GHCR)**

- `update-gitops.yml`
  - Tras un CI exitoso, actualiza automáticamente  
    `gitops/workloads/listmonk/kustomization.yaml` con el nuevo tag (SHA)
  - Abre un **Pull Request** en este mismo repositorio

Una vez se mergea el PR, **Argo CD detecta el cambio y despliega la nueva versión**, y **Argo Rollouts** ejecuta el despliegue **Blue/Green**.

---

## 10) Observabilidad

- **Prometheus / Grafana / Alertmanager** vía kube-prometheus-stack
- **Loki** para logs

Acceso rápido (port-forward):

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

---

## 11) Tags AWS

Terraform configura `default_tags` en el provider, de modo que **todos los recursos AWS** incluyen:

- `Project = <project_name>`
- `Environment = <env>`
- `Owner = <owner>`
- `ManagedBy = terraform`

---

## 12) Destrucción del entorno

```bash
cd infra/terraform/envs/dev
terraform destroy -auto-approve
```

---

## Notas de seguridad (anti-patterns evitados)

- ❌ No hay secretos en Git.
- ✅ Pods non-root y `readOnlyRootFilesystem`.
- ✅ IRSA para controllers (AWS Load Balancer Controller, External Secrets).
- ✅ Escaneo de imágenes en CI con Trivy.
