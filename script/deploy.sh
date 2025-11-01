#!/bin/bash

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para imprimir mensajes
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Variables
CLUSTERS=("cluster1" "cluster2" "cluster3")
TIMEOUT=300 # 5 minutos

# Verificar si kubectl está instalado
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl no está instalado o no está en el PATH"
        exit 1
    fi
}

# Verificar conexión al cluster
check_cluster_connection() {
    if ! kubectl cluster-info &> /dev/null; then
        print_error "No se puede conectar al cluster Kubernetes"
        exit 1
    fi
}

# Verificar si ArgoCD está instalado
check_argocd() {
    if ! kubectl get namespace argocd &> /dev/null; then
        print_warning "Namespace argocd no encontrado. Verifica que ArgoCD esté instalado."
        read -p "¿Continuar de todos modos? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Aplicar proyecto ArgoCD
apply_project() {
    print_info "Aplicando proyecto ArgoCD..."
    if kubectl apply -f argocd-project.yaml; then
        print_success "Proyecto ArgoCD aplicado correctamente"
    else
        print_error "Error al aplicar el proyecto ArgoCD"
        exit 1
    fi
}

# Aplicar applications
apply_applications() {
    print_info "Aplicando applications de ArgoCD..."
    for cluster in "${CLUSTERS[@]}"; do
        application_file="applications/${cluster}-application.yaml"
        if [ -f "$application_file" ]; then
            if kubectl apply -f "$application_file"; then
                print_success "Application para $cluster aplicada correctamente"
            else
                print_error "Error al aplicar application para $cluster"
            fi
        else
            print_warning "Archivo $application_file no encontrado"
        fi
    done
}

# Esperar a que las applications estén sincronizadas
wait_for_sync() {
    print_info "Esperando a que las applications se sincronicen..."
    
    for cluster in "${CLUSTERS[@]}"; do
        app_name="rabbitmq-${cluster}"
        print_info "Verificando estado de $app_name..."
        
        # Esperar a que la application exista
        local counter=0
        while ! kubectl get application "$app_name" -n argocd &> /dev/null && [ $counter -lt 30 ]; do
            sleep 5
            ((counter++))
        done
        
        if kubectl get application "$app_name" -n argocd &> /dev/null; then
            # Verificar sincronización
            local sync_status=""
            counter=0
            while [[ "$sync_status" != "Synced" ]] && [ $counter -lt $TIMEOUT ]; do
                sync_status=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
                health_status=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
                
                if [[ "$sync_status" == "Synced" ]] && [[ "$health_status" == "Healthy" ]]; then
                    print_success "$app_name: Sincronizado y Saludable"
                    break
                fi
                
                print_info "$app_name - Sincronización: $sync_status, Salud: $health_status (esperando... $((counter/6))m)"
                sleep 10
                ((counter+=10))
            done
            
            if [[ "$sync_status" != "Synced" ]]; then
                print_warning "$app_name no se sincronizó completamente después de $((TIMEOUT/60)) minutos"
            fi
        else
            print_warning "Application $app_name no encontrada en ArgoCD"
        fi
    done
}

# Verificar estado de los clusters RabbitMQ
check_rabbitmq_clusters() {
    print_info "Verificando estado de los clusters RabbitMQ..."
    
    for cluster in "${CLUSTERS[@]}"; do
        namespace="rabbitmq-${cluster}"
        print_info "Verificando cluster $cluster en namespace $namespace..."
        
        # Esperar a que el namespace exista
        local counter=0
        while ! kubectl get namespace "$namespace" &> /dev/null && [ $counter -lt 60 ]; do
            sleep 5
            ((counter++))
        done
        
        if kubectl get namespace "$namespace" &> /dev/null; then
            # Verificar RabbitMQ cluster
            if kubectl get rabbitmqcluster "$cluster" -n "$namespace" &> /dev/null; then
                print_info "Esperando a que el cluster $cluster esté listo..."
                
                counter=0
                while [ $counter -lt $TIMEOUT ]; do
                    ready=$(kubectl get rabbitmqcluster "$cluster" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
                    
                    if [[ "$ready" == "True" ]]; then
                        print_success "Cluster $cluster está listo"
                        break
                    fi
                    
                    # Mostrar estado de los pods
                    running_pods=$(kubectl get pods -n "$namespace" -l app.kubernetes.io/name="$cluster" --field-selector=status.phase=Running --no-headers | wc -l)
                    total_pods=$(kubectl get pods -n "$namespace" -l app.kubernetes.io/name="$cluster" --no-headers | wc -l)
                    
                    print_info "Cluster $cluster - Listo: $ready, Pods: $running_pods/$total_pods (esperando... $((counter/6))m)"
                    sleep 10
                    ((counter+=10))
                done
                
                if [[ "$ready" != "True" ]]; then
                    print_warning "Cluster $cluster no está listo después de $((TIMEOUT/60)) minutos"
                fi
            else
                print_warning "RabbitMQCluster $cluster no encontrado en namespace $namespace"
            fi
        else
            print_warning "Namespace $namespace no encontrado"
        fi
    done
}

# Mostrar resumen final
show_summary() {
    echo ""
    print_success "=== RESUMEN DEL DESPLIEGUE ==="
    
    # Estado de las applications de ArgoCD
    print_info "Applications de ArgoCD:"
    kubectl get applications -n argocd -l app.kubernetes.io/part-of=rabbitmq-clusters 2>/dev/null || kubectl get applications -n argocd | grep rabbitmq
    
    echo ""
    
    # Estado de los clusters RabbitMQ
    print_info "Clusters RabbitMQ:"
    for cluster in "${CLUSTERS[@]}"; do
        namespace="rabbitmq-${cluster}"
        if kubectl get namespace "$namespace" &> /dev/null; then
            echo -n "🔍 $cluster: "
            if kubectl get rabbitmqcluster "$cluster" -n "$namespace" &> /dev/null; then
                ready=$(kubectl get rabbitmqcluster "$cluster" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
                echo -e "Namespace: $namespace, Estado: $ready"
            else
                echo -e "Namespace: $namespace, Cluster: No encontrado"
            fi
        else
            echo -e "❌ $cluster: Namespace $namespace no encontrado"
        fi
    done
    
    echo ""
    print_info "Para ver más detalles:"
    echo "  kubectl get rabbitmqcluster -A"
    echo "  kubectl get pods -n rabbitmq-cluster1"
    echo "  argocd app list"
}

# Función principal
main() {
    echo -e "${GREEN}"
    cat << "EOF"
🚀 Iniciando despliegue de clusters RabbitMQ con ArgoCD
EOF
    echo -e "${NC}"
    
    # Verificaciones iniciales
    check_kubectl
    check_cluster_connection
    check_argocd
    
    # Aplicar configuración
    apply_project
    apply_applications
    
    # Esperar sincronización
    wait_for_sync
    
    # Verificar clusters
    check_rabbitmq_clusters
    
    # Mostrar resumen
    show_summary
    
    print_success "Despliegue completado! 🎉"
}

# Manejar argumentos
case "${1:-}" in
    -h|--help)
        echo "Uso: $0 [OPCIONES]"
        echo ""
        echo "Opciónes:"
        echo "  -h, --help     Mostrar esta ayuda"
        echo "  -f, --force    Continuar sin confirmaciones"
        echo ""
        echo "Este script despliega 3 clusters de RabbitMQ usando ArgoCD."
        exit 0
        ;;
    -f|--force)
        # Ejecutar sin confirmaciones
        main
        ;;
    *)
        read -p "¿Deseas desplegar los clusters RabbitMQ? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            main
        else
            print_info "Despliegue cancelado"
            exit 0
        fi
        ;;
esac
