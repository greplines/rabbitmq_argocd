# RabbitMQ Clusters con ArgoCD

Este proyecto despliega 3 clusters de RabbitMQ en Kubernetes usando ArgoCD para GitOps.

## Estructura

rabbitmq-clusters/
├── applications/ # Applications de ArgoCD
├── manifests/ # Manifiestos Kubernetes por cluster
├── scripts/ # Scripts de utilidad
├── argocd-project.yaml # Proyecto ArgoCD
└── kustomization.yaml # Kustomize raiz


## 🚀 Despliegue Rápido

### Prerrequisitos
- Kubernetes cluster
- ArgoCD instalado
- RabbitMQ Operator instalado

### Desplegar
```bash
# Usar el script de despliegue
./scripts/deploy.sh

# O manualmente
kubectl apply -f argocd-project.yaml
kubectl apply -f applications/

Scripts de Utilidad

    scripts/deploy.sh - Despliega los clusters

    scripts/get-credentials.sh - Obtiene credenciales de los clusters


## Verificacion

# Verificar applications de ArgoCD
argocd app list

# Verificar clusters RabbitMQ
kubectl get rabbitmqcluster -A

# Verificar pods
kubectl get pods -n rabbitmq-cluster1
