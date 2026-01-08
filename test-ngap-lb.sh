#!/bin/bash

# NGAP Load Balancing Test Suite
# Tests 100 concurrent UE connections through loxilb

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# echo_info prints an informational message prefixed with a green `[INFO]` tag.
echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
# echo_warn prints a warning message prefixed with `[WARN]` in yellow.
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
# echo_error prints the provided message prefixed with `[ERROR]` in red.
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load environment
source .env.ngap-lb

NUM_UES=${1:-100}
PCAP_DIR="$SCRIPT_DIR/pcap_captures"
mkdir -p "$PCAP_DIR"

case "${1:-}" in
    "install-tcpdump")
        echo_info "Installing tcpdump in containers..."
        for container in loxilb amf1 amf2; do
            echo_info "Installing in $container..."
            docker exec $container apt-get update -qq
            docker exec $container apt-get install -y -qq tcpdump
        done
        echo_info "tcpdump installed in all containers"
        ;;

    "start-capture")
        echo_info "Starting packet captures..."
        docker exec -d loxilb tcpdump -i any sctp -w /tmp/loxilb_ngap.pcap
        docker exec -d amf1 tcpdump -i any port 38412 -w /tmp/amf1_ngap.pcap
        docker exec -d amf2 tcpdump -i any port 38412 -w /tmp/amf2_ngap.pcap
        echo_info "Packet captures running in background"
        ;;

    "stop-capture")
        echo_info "Stopping packet captures and extracting files..."
        # Kill tcpdump processes
        docker exec loxilb pkill tcpdump || true
        docker exec amf1 pkill tcpdump || true
        docker exec amf2 pkill tcpdump || true
        sleep 2

        # Copy pcap files
        docker cp loxilb:/tmp/loxilb_ngap.pcap "$PCAP_DIR/" 2>/dev/null || echo_warn "No loxilb pcap"
        docker cp amf1:/tmp/amf1_ngap.pcap "$PCAP_DIR/" 2>/dev/null || echo_warn "No amf1 pcap"
        docker cp amf2:/tmp/amf2_ngap.pcap "$PCAP_DIR/" 2>/dev/null || echo_warn "No amf2 pcap"

        echo_info "Packet captures saved to $PCAP_DIR/"
        ls -la "$PCAP_DIR/"
        ;;

    "add-subscribers")
        NUM=${2:-100}
        echo_info "Adding $NUM subscribers to database..."
        for i in $(seq -w 1 $NUM); do
            docker exec webui /open5gs/misc/db/open5gs-dbctl \
                --db_uri=mongodb://172.22.0.2/open5gs \
                add 0010112345678${i} 8baf473f2f8fd09487cccbd7097c6862 11111111111111111111111111111111 2>/dev/null
        done
        echo_info "Added $NUM subscribers"
        ;;

    "spawn-ues")
        NUM=${2:-10}
        echo_info "Spawning $NUM UE containers..."

        # Base IP for UEs: 172.22.0.200+
        for i in $(seq 1 $NUM); do
            UE_IP="172.22.0.$((200 + i))"
            IMSI=$(printf "00101123456780%02d" $i)
            CONTAINER_NAME="nr_ue_$i"

            # Skip if container exists
            if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
                echo_warn "Container $CONTAINER_NAME already exists, skipping"
                continue
            fi

            echo_info "Starting UE $i (IMSI: $IMSI, IP: $UE_IP)..."

            docker run -d \
                --name "$CONTAINER_NAME" \
                --network docker_open5gs_default \
                --ip "$UE_IP" \
                --cap-add NET_ADMIN \
                --device /dev/net/tun \
                --privileged \
                -e MCC=001 \
                -e MNC=01 \
                -e UE1_IMSI="$IMSI" \
                -e UE1_KI="8baf473f2f8fd09487cccbd7097c6862" \
                -e UE1_OP="11111111111111111111111111111111" \
                -e UE1_AMF="8000" \
                -e UE1_IMEI="356938035643803" \
                -e UE1_IMEISV="4370816125816151" \
                -e NR_GNB_IP="172.22.0.23" \
                -e COMPONENT_NAME="ueransim-ue" \
                -v "$SCRIPT_DIR/ueransim:/mnt/ueransim:ro" \
                docker_ueransim \
                /ueransim_image_init.sh >/dev/null 2>&1

            # Small delay to avoid overwhelming the gNB
            sleep 0.5
        done

        echo_info "Spawned $NUM UE containers"
        ;;

    "cleanup-ues")
        echo_info "Removing all test UE containers..."
        docker ps -a --format '{{.Names}}' | grep "^nr_ue_" | xargs -r docker rm -f
        echo_info "Cleanup complete"
        ;;

    "status")
        echo ""
        echo "========== NGAP Load Balancing Test Status =========="
        echo ""

        echo "=== loxilb LB Rules ==="
        docker exec loxilb loxicmd get lb -o wide

        echo ""
        echo "=== Active SCTP Connections ==="
        docker exec loxilb loxicmd get ct | head -20

        echo ""
        echo "=== Running UE Containers ==="
        docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "nr_ue" | wc -l
        echo "UE containers running"

        echo ""
        echo "=== AMF Connection Distribution ==="
        echo "AMF1 connections:"
        docker exec amf1 netstat -an 2>/dev/null | grep ":38412" | grep ESTABLISHED | wc -l || echo "0"
        echo "AMF2 connections:"
        docker exec amf2 netstat -an 2>/dev/null | grep ":38412" | grep ESTABLISHED | wc -l || echo "0"

        echo ""
        echo "=== AMF NG Setup Requests ==="
        echo "AMF1: $(docker logs amf1 2>&1 | grep -c 'NG Setup' || echo 0) NG Setup requests"
        echo "AMF2: $(docker logs amf2 2>&1 | grep -c 'NG Setup' || echo 0) NG Setup requests"

        echo ""
        echo "=== Registered UEs ==="
        echo "AMF1: $(docker logs amf1 2>&1 | grep -c 'Registration complete' || echo 0) registrations"
        echo "AMF2: $(docker logs amf2 2>&1 | grep -c 'Registration complete' || echo 0) registrations"
        ;;

    "test-failover")
        echo_info "Testing failover - stopping AMF1..."
        docker stop amf1

        echo_info "Waiting 5 seconds..."
        sleep 5

        echo_info "Restarting gNB to trigger new association..."
        docker restart nr_gnb
        sleep 10

        echo_info "Checking connection tracking (should only show AMF2)..."
        docker exec loxilb loxicmd get ct

        echo_info "Checking AMF2 logs for new connections..."
        docker logs amf2 2>&1 | tail -20

        echo_info "Restoring AMF1..."
        docker start amf1
        sleep 5

        echo_info "Failover test complete"
        ;;

    "test-internal")
        echo_info "Testing internal connectivity (no internet required)..."

        echo ""
        echo "=== gNB -> loxilb connectivity ==="
        docker exec nr_gnb ping -c 2 172.22.0.100

        echo ""
        echo "=== gNB -> VIP routing ==="
        docker exec nr_gnb ip route get 20.20.20.1

        echo ""
        echo "=== UE TUN interface ==="
        docker exec nr_ue ip addr show uesimtun0 2>/dev/null || echo "No TUN interface (UE may not be registered)"

        echo ""
        echo "=== UE -> UPF gateway ping ==="
        docker exec nr_ue ping -c 2 -I uesimtun0 192.168.100.1 2>/dev/null || echo "Cannot reach UPF gateway"

        echo ""
        echo "=== Internal service connectivity ==="
        docker exec nr_ue ping -c 2 172.22.0.26 2>/dev/null && echo "WebUI reachable" || echo "WebUI unreachable"

        echo_info "Internal connectivity test complete"
        ;;

    "full-test")
        echo_info "Running full NGAP load balancing test..."

        # Step 1: Start captures
        $0 start-capture

        # Step 2: Verify initial state
        echo_info "Initial state:"
        $0 status

        # Step 3: Spawn UEs
        NUM_UES=${2:-10}
        $0 spawn-ues $NUM_UES

        # Wait for registrations
        echo_info "Waiting 30 seconds for UE registrations..."
        sleep 30

        # Step 4: Check distribution
        echo_info "Post-test state:"
        $0 status

        # Step 5: Internal connectivity
        $0 test-internal

        echo_info "Full test complete. Run '$0 stop-capture' to extract pcap files."
        ;;

    *)
        echo "NGAP Load Balancing Test Suite"
        echo ""
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  install-tcpdump     Install tcpdump in containers"
        echo "  start-capture       Start background packet captures"
        echo "  stop-capture        Stop captures and extract pcap files"
        echo "  add-subscribers N   Add N subscribers to database"
        echo "  spawn-ues N         Spawn N UE containers (default: 10)"
        echo "  cleanup-ues         Remove all test UE containers"
        echo "  status              Show current LB status and distribution"
        echo "  test-failover       Test AMF failover scenario"
        echo "  test-internal       Test internal connectivity"
        echo "  full-test N         Run full test with N UEs"
        ;;
esac