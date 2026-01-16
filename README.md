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
- `project_name` (default: listmonk2)
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
