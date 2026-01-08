#!/bin/bash

# Kubernetes NGAP Load Balancing Deployment Script
# Uses loxilb as ServiceLB with HPA for auto-scaling AMF pods

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/k8s"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_prerequisites() {
    echo_info "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        echo_error "kubectl not found. Please install kubectl first."
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        echo_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    
    # Check if metrics-server is installed (required for HPA)
    if ! kubectl get deployment metrics-server -n kube-system &> /dev/null; then
        echo_warn "metrics-server not found. HPA won't work without it."
        echo_info "Install with: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
    fi
    
    echo_info "Prerequisites check passed!"
}

deploy_loxilb() {
    echo_info "Deploying loxilb load balancer..."
    
    kubectl apply -f "$K8S_DIR/loxilb-daemonset.yaml"
    kubectl apply -f "$K8S_DIR/kube-loxilb.yaml"
    
    echo_info "Waiting for loxilb to be ready..."
    kubectl rollout status daemonset/loxilb -n kube-system --timeout=120s
    kubectl rollout status deployment/kube-loxilb -n kube-system --timeout=60s
    
    echo_info "loxilb deployed successfully!"
}

deploy_open5gs() {
    echo_info "Deploying Open5GS 5G Core..."
    
    # Create namespace
    kubectl apply -f "$K8S_DIR/namespace.yaml"
    
    # Deploy AMF with ConfigMap
    kubectl apply -f "$K8S_DIR/amf-configmap.yaml"
    kubectl apply -f "$K8S_DIR/amf-deployment.yaml"
    
    # Deploy HPA for auto-scaling
    kubectl apply -f "$K8S_DIR/amf-hpa.yaml"
    
    echo_info "Waiting for AMF to be ready..."
    kubectl rollout status deployment/amf -n open5gs --timeout=120s
    
    echo_info "Open5GS AMF deployed successfully!"
}

show_status() {
    echo ""
    echo "===== Namespace ====="
    kubectl get ns open5gs
    
    echo ""
    echo "===== AMF Pods ====="
    kubectl get pods -n open5gs -l app=amf -o wide
    
    echo ""
    echo "===== AMF Service (LoadBalancer) ====="
    kubectl get svc amf-svc -n open5gs -o wide
    
    echo ""
    echo "===== HPA Status ====="
    kubectl get hpa amf-hpa -n open5gs
    
    echo ""
    echo "===== loxilb Status ====="
    kubectl get pods -n kube-system -l app=loxilb
    
    echo ""
    echo_info "To test auto-scaling, generate load on AMF pods:"
    echo "  kubectl exec -it <amf-pod> -n open5gs -- stress --cpu 2 --timeout 60"
}

scale_test() {
    echo_info "Running scale test - artificially increasing CPU load..."
    
    # Get AMF pod name
    AMF_POD=$(kubectl get pods -n open5gs -l app=amf -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$AMF_POD" ]; then
        echo_error "No AMF pod found"
        exit 1
    fi
    
    echo_info "Installing stress tool in AMF pod..."
    kubectl exec -it "$AMF_POD" -n open5gs -- apt-get update -qq
    kubectl exec -it "$AMF_POD" -n open5gs -- apt-get install -y -qq stress
    
    echo_info "Starting CPU stress test (60 seconds)..."
    echo_info "Watch HPA with: kubectl get hpa amf-hpa -n open5gs -w"
    
    kubectl exec "$AMF_POD" -n open5gs -- stress --cpu 2 --timeout 60 &
    
    # Monitor HPA
    for i in {1..12}; do
        echo ""
        echo "=== HPA Status (t=${i}0s) ==="
        kubectl get hpa amf-hpa -n open5gs
        kubectl get pods -n open5gs -l app=amf
        sleep 10
    done
}

cleanup() {
    echo_info "Cleaning up Kubernetes resources..."
    
    kubectl delete -f "$K8S_DIR/amf-hpa.yaml" --ignore-not-found
    kubectl delete -f "$K8S_DIR/amf-deployment.yaml" --ignore-not-found
    kubectl delete -f "$K8S_DIR/amf-configmap.yaml" --ignore-not-found
    kubectl delete -f "$K8S_DIR/namespace.yaml" --ignore-not-found
    kubectl delete -f "$K8S_DIR/kube-loxilb.yaml" --ignore-not-found
    kubectl delete -f "$K8S_DIR/loxilb-daemonset.yaml" --ignore-not-found
    
    echo_info "Cleanup complete!"
}

case "${1:-}" in
    "prereq")
        check_prerequisites
        ;;
    "deploy-lb")
        check_prerequisites
        deploy_loxilb
        ;;
    "deploy")
        check_prerequisites
        deploy_loxilb
        deploy_open5gs
        show_status
        ;;
    "status")
        show_status
        ;;
    "scale-test")
        scale_test
        ;;
    "cleanup")
        cleanup
        ;;
    *)
        echo "Kubernetes NGAP Load Balancing with loxilb + HPA"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  prereq      Check prerequisites (kubectl, cluster, metrics-server)"
        echo "  deploy-lb   Deploy loxilb load balancer only"
        echo "  deploy      Deploy full stack (loxilb + Open5GS AMF + HPA)"
        echo "  status      Show deployment status"
        echo "  scale-test  Run CPU stress test to trigger HPA scaling"
        echo "  cleanup     Remove all deployed resources"
        echo ""
        echo "Architecture:"
        echo "  - loxilb: eBPF-based ServiceLB with SCTP support"
        echo "  - kube-loxilb: Controller for Service discovery"
        echo "  - AMF: Deployment with HPA (scales 1-5 pods based on CPU/memory)"
        echo ""
        echo "HPA Settings:"
        echo "  - Scale up when CPU > 70% or Memory > 80%"
        echo "  - Min replicas: 1, Max replicas: 5"
        echo "  - Scale down stabilization: 5 minutes"
        ;;
esac
