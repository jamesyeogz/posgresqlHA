#!/bin/bash

# Patroni PostgreSQL HA Cluster with Supabase Setup Script
# This script automates the deployment of the entire stack with Consul

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to wait for pods to be ready
wait_for_pods() {
    local label=$1
    local namespace=${2:-default}
    local timeout=${3:-300}
    
    print_status "Waiting for pods with label $label to be ready..."
    kubectl wait --for=condition=ready pod -l "$label" -n "$namespace" --timeout="${timeout}s"
}

# Function to wait for deployment to be ready
wait_for_deployment() {
    local deployment=$1
    local namespace=${2:-default}
    local timeout=${3:-300}
    
    print_status "Waiting for deployment $deployment to be ready..."
    kubectl wait --for=condition=available deployment "$deployment" -n "$namespace" --timeout="${timeout}s"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    local missing_tools=()
    
    if ! command_exists docker; then
        missing_tools+=("docker")
    fi
    
    if ! command_exists docker-compose; then
        missing_tools+=("docker-compose")
    fi
    
    if ! command_exists kubectl; then
        missing_tools+=("kubectl")
    fi
    
    if ! command_exists helm; then
        missing_tools+=("helm")
    fi
    
    if ! command_exists minikube; then
        missing_tools+=("minikube")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_error "Please install the missing tools and run this script again."
        exit 1
    fi
    
    print_success "All prerequisites are installed"
}

# Start Minikube
start_minikube() {
    print_status "Starting Minikube..."
    
    if minikube status | grep -q "Running"; then
        print_success "Minikube is already running"
    else
        minikube start --driver=docker --kubernetes-version=v1.30.0
        print_success "Minikube started successfully"
    fi
    
    # Get Minikube IP
    MINIKUBE_IP=$(minikube ip)
    print_status "Minikube IP: $MINIKUBE_IP"
    
    # Update docker-compose files with correct Consul endpoint
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        for vm in vm1 vm2 vm3; do
            if [ -f "docker-compose.$vm.yml" ]; then
                sed -i '' "s/CONSUL_HOST: \${CONSUL_HOST:-.*}/CONSUL_HOST: \${CONSUL_HOST:-$MINIKUBE_IP:32500}/g" docker-compose.$vm.yml
            fi
        done
    else
        # Linux
        for vm in vm1 vm2 vm3; do
            if [ -f "docker-compose.$vm.yml" ]; then
                sed -i "s/CONSUL_HOST: \${CONSUL_HOST:-.*}/CONSUL_HOST: \${CONSUL_HOST:-$MINIKUBE_IP:32500}/g" docker-compose.$vm.yml
            fi
        done
    fi
    
    print_success "Updated docker-compose files with Minikube IP"
}

# Deploy Consul cluster
deploy_consul() {
    print_status "Deploying Consul cluster..."
    
    kubectl apply -f k8s/consul-cluster.yaml
    
    # Wait for Consul pods to be ready
    wait_for_pods "app=consul" "default" 300
    
    print_success "Consul cluster deployed successfully"
    
    # Verify Consul cluster health
    print_status "Verifying Consul cluster health..."
    kubectl exec consul-0 -- consul members
    print_success "Consul cluster is healthy"
    
    # Show Consul UI access
    print_status "Consul UI will be available at:"
    echo "  kubectl port-forward svc/consul-ui 8500:8500"
    echo "  Then open http://localhost:8500 in your browser"
}

# Deploy HAProxy
deploy_haproxy() {
    print_status "Deploying HAProxy..."
    
    kubectl apply -f k8s/haproxy-deployment.yaml
    
    # Wait for HAProxy deployment to be ready
    wait_for_deployment "haproxy" "default" 300
    
    print_success "HAProxy deployed successfully"
}

# Build and deploy Patroni cluster (Per-VM)
deploy_patroni() {
    print_status "Building Patroni Docker image..."
    
    docker build -f docker/Dockerfile.patroni -t patroni-postgres .
    
    print_success "Patroni Docker image built successfully"
    
    print_status "Starting Patroni PostgreSQL cluster on all VMs..."
    
    # Deploy on each VM
    for vm in vm1 vm2 vm3; do
        if [ -f "docker-compose.$vm.yml" ]; then
            print_status "Deploying on VM $vm..."
            docker-compose -f docker-compose.$vm.yml up -d
            
            # Wait for container to be healthy
            sleep 10
            
            if docker-compose -f docker-compose.$vm.yml ps | grep -q "Up"; then
                print_success "Patroni on VM $vm started successfully"
            else
                print_error "Failed to start Patroni on VM $vm"
                docker-compose -f docker-compose.$vm.yml logs
                exit 1
            fi
        else
            print_warning "docker-compose.$vm.yml not found, skipping VM $vm"
        fi
    done
    
    # Wait for cluster to form
    print_status "Waiting for Patroni cluster to form..."
    sleep 60
    
    # Check cluster status
    print_status "Checking Patroni cluster status..."
    if docker exec patroni-postgres-vm1 patronictl list 2>/dev/null; then
        print_success "Patroni cluster is running and healthy"
    else
        print_warning "Patroni cluster might still be initializing. Check logs with:"
        echo "  docker-compose -f docker-compose.vm1.yml logs"
    fi
}

# Initialize Supabase database
init_supabase_db() {
    print_status "Initializing Supabase database schema..."
    
    # Wait for PostgreSQL to be ready on primary VM
    print_status "Waiting for PostgreSQL to be ready on VM1..."
    for i in {1..30}; do
        if docker exec patroni-postgres-vm1 pg_isready -U postgres >/dev/null 2>&1; then
            break
        fi
        sleep 5
    done
    
    # Run the initialization script
    if docker exec -i patroni-postgres-vm1 psql -U postgres < scripts/init-supabase-db.sql; then
        print_success "Supabase database schema initialized successfully"
    else
        print_error "Failed to initialize Supabase database schema"
        exit 1
    fi
}

# Deploy Supabase
deploy_supabase() {
    print_status "Adding Supabase Helm repository..."
    
    helm repo add supabase https://supabase.github.io/supabase-kubernetes 2>/dev/null || true
    helm repo update
    
    print_status "Deploying Supabase..."
    
    # Check if Supabase is already installed
    if helm list | grep -q supabase; then
        print_status "Supabase is already installed, upgrading..."
        helm upgrade supabase supabase/supabase -f supabase-helm/values-patroni.yaml
    else
        helm install supabase supabase/supabase -f supabase-helm/values-patroni.yaml
    fi
    
    # Wait for Supabase deployments to be ready
    print_status "Waiting for Supabase services to be ready..."
    
    # Wait for key services
    wait_for_deployment "supabase-auth" "default" 300
    wait_for_deployment "supabase-rest" "default" 300
    wait_for_deployment "supabase-studio" "default" 300
    wait_for_deployment "supabase-kong" "default" 300
    
    print_success "Supabase deployed successfully"
}

# Display access information
show_access_info() {
    print_success "Setup completed successfully!"
    echo
    print_status "Access Information:"
    echo
    
    # Get Minikube IP
    MINIKUBE_IP=$(minikube ip)
    
    echo -e "${GREEN}PostgreSQL Cluster:${NC}"
    echo "  Primary (Read/Write): localhost:5432"
    echo "  Replica 1: localhost:5433"
    echo "  Replica 2: localhost:5434"
    echo "  Username: postgres"
    echo "  Password: password"
    echo
    
    echo -e "${GREEN}HAProxy Statistics:${NC}"
    echo "  URL: http://localhost:7000"
    echo "  Username: admin"
    echo "  Password: password"
    echo "  Command: kubectl port-forward svc/haproxy-stats 7000:7000"
    echo
    
    echo -e "${GREEN}Supabase Studio:${NC}"
    echo "  URL: http://localhost:3000"
    echo "  Command: kubectl port-forward svc/supabase-studio 3000:3000"
    echo
    
    echo -e "${GREEN}Supabase API Gateway:${NC}"
    echo "  URL: http://localhost:8000"
    echo "  Command: kubectl port-forward svc/supabase-kong 8000:8000"
    echo
    
    echo -e "${GREEN}Consul Cluster:${NC}"
    echo "  Endpoint: $MINIKUBE_IP:32500"
    echo "  UI: http://localhost:8500"
    echo "  Command: kubectl port-forward svc/consul-ui 8500:8500"
    echo "  Health Check: kubectl exec consul-0 -- consul members"
    echo
    
    print_status "Useful Commands:"
    echo "  Check Patroni cluster: docker exec patroni-postgres-vm1 patronictl list"
    echo "  Check Kubernetes pods: kubectl get pods"
    echo "  Check Consul services: kubectl exec consul-0 -- consul catalog services"
    echo "  Check Supabase services: kubectl get svc -l app.kubernetes.io/name=supabase"
    echo "  View logs (VM1): docker-compose -f docker-compose.vm1.yml logs -f"
    echo "  Stop everything: for vm in vm1 vm2 vm3; do docker-compose -f docker-compose.$vm.yml down; done && kubectl delete -f k8s/"
}

# Main execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Patroni PostgreSQL HA + Supabase Setup${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    
    # Parse command line arguments
    SKIP_PREREQUISITES=false
    SKIP_MINIKUBE=false
    SKIP_CONSUL=false
    SKIP_HAPROXY=false
    SKIP_PATRONI=false
    SKIP_SUPABASE_DB=false
    SKIP_SUPABASE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-prerequisites)
                SKIP_PREREQUISITES=true
                shift
                ;;
            --skip-minikube)
                SKIP_MINIKUBE=true
                shift
                ;;
            --skip-consul)
                SKIP_CONSUL=true
                shift
                ;;
            --skip-haproxy)
                SKIP_HAPROXY=true
                shift
                ;;
            --skip-patroni)
                SKIP_PATRONI=true
                shift
                ;;
            --skip-supabase-db)
                SKIP_SUPABASE_DB=true
                shift
                ;;
            --skip-supabase)
                SKIP_SUPABASE=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --skip-prerequisites  Skip prerequisite checks"
                echo "  --skip-minikube      Skip Minikube setup"
                echo "  --skip-consul       Skip Consul deployment"
                echo "  --skip-haproxy       Skip HAProxy deployment"
                echo "  --skip-patroni       Skip Patroni deployment"
                echo "  --skip-supabase-db   Skip Supabase database initialization"
                echo "  --skip-supabase      Skip Supabase deployment"
                echo "  --help               Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute setup steps
    if [ "$SKIP_PREREQUISITES" = false ]; then
        check_prerequisites
    fi
    
    if [ "$SKIP_MINIKUBE" = false ]; then
        start_minikube
    fi
    
    if [ "$SKIP_CONSUL" = false ]; then
        deploy_consul
    fi
    
    if [ "$SKIP_HAPROXY" = false ]; then
        deploy_haproxy
    fi
    
    if [ "$SKIP_PATRONI" = false ]; then
        deploy_patroni
    fi
    
    if [ "$SKIP_SUPABASE_DB" = false ]; then
        init_supabase_db
    fi
    
    if [ "$SKIP_SUPABASE" = false ]; then
        deploy_supabase
    fi
    
    show_access_info
}

# Run main function with all arguments
main "$@"
