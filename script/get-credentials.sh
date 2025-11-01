#!/bin/bash

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
SHOW_ONLY=""
NAMESPACE_PREFIX="rabbitmq"

# Mostrar ayuda
show_help() {
    echo "Uso: $0 [OPCIONES]"
    echo ""
    echo "Opciones:"
    echo "  -c, --cluster CLUSTER    Mostrar solo un cluster específico (cluster1, cluster2, cluster3)"
    echo "  -u, --user               Mostrar solo usernames"
    echo "  -p, --password           Mostrar solo passwords"
    echo "  -n, --namespace PREFIJO  Prefijo del namespace (default: rabbitmq)"
    echo "  -h, --help               Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  $0                        # Mostrar todas las credenciales"
    echo "  $0 -c cluster1            # Mostrar solo cluster1"
    echo "  $0 --user                 # Mostrar solo usernames"
    echo "  $0 -n mi-namespace        # Usar prefijo de namespace diferente"
    echo "  $0 -c cluster2 --password # Mostrar solo password de cluster2"
}

# Parsear argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--cluster)
            CLUSTERS=("$2")
            shift 2
            ;;
        -u|--user)
            SHOW_ONLY="user"
            shift
            ;;
        -p|--password)
            SHOW_ONLY="password"
            shift
            ;;
        -n|--namespace)
            NAMESPACE_PREFIX="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            print_error "Opción desconocida: $1"
            show_help
            exit 1
            ;;
    esac
done

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

# Obtener credenciales de un cluster
get_cluster_credentials() {
    local cluster="$1"
    local namespace="${NAMESPACE_PREFIX}-${cluster}"
    local secret_name="${cluster}-default-user"
    
    # Verificar si el namespace existe
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        print_warning "Namespace $namespace no existe para el cluster $cluster"
        return 1
    fi
    
    # Verificar si el secreto existe
    if ! kubectl get secret "$secret_name" -n "$namespace" &> /dev/null; then
        print_warning "Secret $secret_name no encontrado en namespace $namespace"
        return 1
    fi
    
    # Obtener username
    local username
    username=$(kubectl get secret "$secret_name" -n "$namespace" -o jsonpath="{.data.username}" 2>/dev/null | base64 -d 2>/dev/null)
    
    # Obtener password
    local password
    password=$(kubectl get secret "$secret_name" -n "$namespace" -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)
    
    # Verificar que se obtuvieron las credenciales
    if [ -z "$username" ] && [ -z "$password" ]; then
        print_warning "No se pudieron obtener las credenciales para $cluster"
        return 1
    fi
    
    # Mostrar según la opción seleccionada
    case "$SHOW_ONLY" in
        "user")
            if [ -n "$username" ]; then
                echo "$username"
            fi
            ;;
        "password")
            if [ -n "$password" ]; then
                echo "$password"
            fi
            ;;
        *)
            echo "=== $cluster ==="
            echo "Namespace: $namespace"
            if [ -n "$username" ]; then
                echo "Username: $username"
            else
                echo "Username: ❌ No disponible"
            fi
            if [ -n "$password" ]; then
                echo "Password: $password"
            else
                echo "Password: ❌ No disponible"
            fi
            echo ""
            ;;
    esac
    
    return 0
}

# Función para mostrar en formato tabla
show_table_format() {
    local success_count=0
    
    echo "CLUSTER    | NAMESPACE           | USERNAME | PASSWORD"
    echo "-----------|---------------------|----------|----------"
    
    for cluster in "${CLUSTERS[@]}"; do
        local namespace="${NAMESPACE_PREFIX}-${cluster}"
        local secret_name="${cluster}-default-user"
        
        if kubectl get namespace "$namespace" &> /dev/null && \
           kubectl get secret "$secret_name" -n "$namespace" &> /dev/null; then
            
            local username
            username=$(kubectl get secret "$secret_name" -n "$namespace" -o jsonpath="{.data.username}" 2>/dev/null | base64 -d 2>/dev/null)
            
            local password
            password=$(kubectl get secret "$secret_name" -n "$namespace" -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)
            
            printf "%-10s | %-19s | %-8s | %s\n" \
                   "$cluster" \
                   "$namespace" \
                   "${username:-❌}" \
                   "${password:0:8}..."  # Mostrar solo primeros 8 caracteres del password
            
            ((success_count++))
        else
            printf "%-10s | %-19s | %-8s | %s\n" \
                   "$cluster" \
                   "$namespace" \
                   "❌" \
                   "❌"
        fi
    done
    
    echo ""
    print_info "Se encontraron credenciales para $success_count de ${#CLUSTERS[@]} clusters"
}

# Función principal
main() {
    check_kubectl
    check_cluster_connection
    
    print_info "Obteniendo credenciales de los clusters RabbitMQ..."
    echo ""
    
    # Si se solicita solo user o password, mostrar en formato simple
    if [[ "$SHOW_ONLY" == "user" || "$SHOW_ONLY" == "password" ]]; then
        for cluster in "${CLUSTERS[@]}"; do
            get_cluster_credentials "$cluster"
        done
    else
        # Mostrar en formato detallado
        local found_any=0
        for cluster in "${CLUSTERS[@]}"; do
            if get_cluster_credentials "$cluster"; then
                found_any=1
            fi
        done
        
        if [ $found_any -eq 0 ]; then
            print_error "No se encontraron credenciales para ninguno de los clusters"
            echo ""
            print_info "Verifica que:"
            echo "  1. Los clusters estén desplegados"
            echo "  2. Los namespaces existan: ${NAMESPACE_PREFIX}-cluster{1,2,3}"
            echo "  3. Los secrets estén creados: cluster{1,2,3}-default-user"
            exit 1
        fi
        
        # Mostrar también en formato tabla
        echo "----------------------------------------"
        show_table_format
    fi
}

# Ejecutar función principal
main
