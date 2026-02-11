#!/bin/bash
# Script to update Linux router configuration without redeploying the lab

set -e

ROUTER_CONTAINER="clab-calico-dscp-router"

echo "=== Updating Linux Router Configuration ==="
echo "Router container: $ROUTER_CONTAINER"
echo ""

# Check if container exists
if ! docker ps --format "{{.Names}}" | grep -q "^${ROUTER_CONTAINER}$"; then
    echo "Error: Router container '$ROUTER_CONTAINER' not found!"
    echo "Make sure the lab is deployed first."
    exit 1
fi

echo "[1/6] Removing old tc configuration..."
docker exec $ROUTER_CONTAINER sh -c "
    # Remove existing qdiscs (this removes all filters and classes too)
    tc qdisc del dev eth3 root 2>/dev/null || true
    tc qdisc del dev eth2 root 2>/dev/null || true
    tc qdisc del dev eth1 root 2>/dev/null || true
    tc qdisc del dev br-cluster root 2>/dev/null || true
" || echo "  (No existing qdiscs to remove)"

echo "[2/6] Cleaning up old bridge configuration..."
docker exec $ROUTER_CONTAINER sh -c "
    # Remove IP from bridge if it exists
    ip addr del 10.10.10.1/24 dev br-cluster 2>/dev/null || true
    # Remove IPs from individual interfaces if they exist
    ip addr del 10.10.10.1/24 dev eth1 2>/dev/null || true
    ip addr del 10.10.10.2/24 dev eth2 2>/dev/null || true
    # Remove bridge if it exists
    ip link set dev br-cluster down 2>/dev/null || true
    ip link delete br-cluster 2>/dev/null || true
"

echo "[3/6] Setting up bridge..."
docker exec $ROUTER_CONTAINER sh -c "
    # Create bridge
    ip link add name br-cluster type bridge
    # Add interfaces to bridge
    ip link set dev eth1 master br-cluster
    ip link set dev eth2 master br-cluster
    # Bring interfaces up
    ip link set dev br-cluster up
    ip link set dev eth1 up
    ip link set dev eth2 up
    # Add IP only on bridge
    ip addr add dev br-cluster 10.10.10.1/24
"

echo "[4/6] Configuring eth3 (client-facing interface)..."
docker exec $ROUTER_CONTAINER sh -c "
    # Ensure eth3 is up and has correct IP
    ip link set dev eth3 up
    ip addr add dev eth3 10.30.30.1/24 2>/dev/null || ip addr change dev eth3 10.30.30.1/24
"

echo "[5/6] Enabling IP forwarding..."
docker exec $ROUTER_CONTAINER sh -c "
    sysctl -w net.ipv4.ip_forward=1
"

echo "[6/6] Configuring DSCP-based QoS with Linux tc..."
docker exec $ROUTER_CONTAINER sh -c "
    # Add HTB qdisc
    tc qdisc add dev eth3 root handle 1: htb default 30
    
    # Create root class
    tc class add dev eth3 parent 1: classid 1:1 htb rate 1000mbit
    
    # Create classes for different DSCP values
    tc class add dev eth3 parent 1:1 classid 1:10 htb rate 1mbit ceil 1mbit    # AF11
    tc class add dev eth3 parent 1:1 classid 1:20 htb rate 5mbit ceil 5mbit    # EF
    tc class add dev eth3 parent 1:1 classid 1:30 htb rate 1000mbit             # Default
    
    # Add filters to match DSCP values (TOS byte)
    # AF11: DSCP 10 = 0x28 in TOS byte (10 << 2)
    tc filter add dev eth3 protocol ip parent 1:0 prio 1 u32 match ip tos 0x28 0xff flowid 1:10
    
    # EF: DSCP 46 = 0xb8 in TOS byte (46 << 2)
    tc filter add dev eth3 protocol ip parent 1:0 prio 2 u32 match ip tos 0xb8 0xff flowid 1:20
"

echo ""
echo "=== Verifying Configuration ==="
echo ""
echo "Bridge configuration:"
docker exec $ROUTER_CONTAINER ip addr show br-cluster
echo ""
echo "Interface configuration:"
docker exec $ROUTER_CONTAINER ip addr show eth3
echo ""
echo "Routes:"
docker exec $ROUTER_CONTAINER ip route show
echo ""
echo "TC qdisc:"
docker exec $ROUTER_CONTAINER tc qdisc show dev eth3
echo ""
echo "TC classes:"
docker exec $ROUTER_CONTAINER tc class show dev eth3
echo ""
echo "TC filters:"
docker exec $ROUTER_CONTAINER tc filter show dev eth3
echo ""
echo "================================================================"
echo "Router configuration updated successfully!"
echo "================================================================"
echo ""
echo "You can now test DSCP throttling:"
echo "  1. Start iperf3 server: sudo docker exec -it clab-calico-dscp-client iperf3 -s"
echo "  2. Test AF11 (1 Mbps): kubectl exec -it sender-dscp-af11 -- iperf3 -c 10.30.30.100 -t 10"
echo "  3. Test EF (5 Mbps): kubectl exec -it sender-dscp-ef -- iperf3 -c 10.30.30.100 -t 10"
echo ""
