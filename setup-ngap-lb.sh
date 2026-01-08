#!/bin/bash

# NGAP Load Balancing Setup Script
# This script sets up loxilb for SCTP/NGAP load balancing across multiple AMF instances
# Mode: LEAST-CONNECTIONS (LC) - Routes to AMF with fewest active connections

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load environment variables
if [ -f .env.ngap-lb ]; then
    set -a
    source .env.ngap-lb
    set +a
    echo_info "Loaded environment from .env.ngap-lb"
else
    echo_error ".env.ngap-lb not found!"
    exit 1
fi

# Function to wait for container to be ready
wait_for_container() {
    local container=$1
    local max_attempts=30
    local attempt=1

    echo_info "Waiting for $container to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null | grep -q true; then
            echo_info "$container is running"
            return 0
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    echo_error "$container failed to start"
    return 1
}

# Function to configure loxilb
configure_loxilb() {
    echo_info "Configuring loxilb SCTP load balancer..."

    # Wait for loxilb to be ready
    sleep 5

    # Add VIP address to loxilb
    echo_info "Adding VIP ${LOXILB_VIP} to loxilb..."
    docker exec loxilb ip addr add ${LOXILB_VIP}/32 dev lo || true

    # Create SCTP load balancer rule for NGAP (port 38412)
    echo_info "Creating SCTP LB rule for NGAP (least-connections mode)..."
    docker exec loxilb loxicmd create lb ${LOXILB_VIP} \
        --sctp=38412:38412 \
        --endpoints=${AMF1_IP}:1,${AMF2_IP}:1 \
        --mode=onearm \
        --select=lc

    echo_info "loxilb configuration complete!"

    # Display the LB rule
    echo_info "Current LB rules:"
    docker exec loxilb loxicmd get lb -o wide
}

# Function to verify setup
verify_setup() {
    echo_info "Verifying setup..."

    echo ""
    echo "===== loxilb Status ====="
    docker exec loxilb loxicmd get lb -o wide

    echo ""
    echo "===== Container Status ====="
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "loxilb|amf|nr_gnb"

    echo ""
    echo_info "Setup complete!"
    echo ""
    echo "Next steps:"
    echo "1. Open WebUI at http://localhost:9999 (admin/1423)"
    echo "2. Add a subscriber with IMSI: ${UE1_IMSI}"
    echo "3. Start gNB and UE with: docker compose -f ngap-lb-deploy.yaml up nr_gnb nr_ue -d"
    echo "4. Monitor loxilb connections: docker exec loxilb loxicmd get ct"
}

# Main execution
case "${1:-}" in
    "build")
        echo_info "Building Open5GS and UERANSIM images..."
        docker compose -f sa-deploy.yaml build
        docker compose -f nr-gnb.yaml build
        ;;
    "start")
        echo_info "Starting NGAP load balancing deployment..."
        # Copy env file
        cp .env.ngap-lb .env

        # Start core services first
        docker compose -f ngap-lb-deploy.yaml up -d mongo nrf scp
        sleep 10

        # Start remaining 5G core NFs
        docker compose -f ngap-lb-deploy.yaml up -d ausf udr udm pcf bsf nssf
        sleep 5

        # Start loxilb and AMFs
        docker compose -f ngap-lb-deploy.yaml up -d loxilb amf1 amf2
        sleep 10

        # Configure loxilb
        configure_loxilb

        # Start SMF, UPF, and WebUI
        docker compose -f ngap-lb-deploy.yaml up -d smf upf webui
        sleep 5

        verify_setup
        ;;
    "stop")
        echo_info "Stopping all containers..."
        docker compose -f ngap-lb-deploy.yaml down
        ;;
    "status")
        verify_setup
        ;;
    "configure-lb")
        configure_loxilb
        ;;
    "gnb")
        echo_info "Starting UERANSIM gNB..."
        docker compose -f ngap-lb-deploy.yaml up -d nr_gnb
        sleep 3
        echo_info "gNB started. Check logs with: docker logs -f nr_gnb"
        ;;
    "ue")
        echo_info "Starting UERANSIM UE..."
        docker compose -f ngap-lb-deploy.yaml up -d nr_ue
        sleep 3
        echo_info "UE started. Check logs with: docker logs -f nr_ue"
        ;;
    "logs")
        container="${2:-loxilb}"
        docker logs -f "$container"
        ;;
    "ct")
        echo_info "loxilb Connection Tracking:"
        docker exec loxilb loxicmd get ct
        ;;
    *)
        echo "NGAP Load Balancing with loxilb - Setup Script"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  build         Build Docker images (Open5GS and UERANSIM)"
        echo "  start         Start full deployment with loxilb LB configuration"
        echo "  stop          Stop all containers"
        echo "  status        Show current status and LB rules"
        echo "  configure-lb  Configure loxilb LB rules (after containers are up)"
        echo "  gnb           Start UERANSIM gNB"
        echo "  ue            Start UERANSIM UE"
        echo "  logs [name]   Follow logs of a container (default: loxilb)"
        echo "  ct            Show loxilb connection tracking table"
        ;;
esac
