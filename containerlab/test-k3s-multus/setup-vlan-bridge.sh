#!/bin/bash
# Script to create VLAN-aware bridge with VLANs 100 and 200 on each Kubernetes node
# Usage: ./setup-vlan-bridge.sh

set -e

# Configuration
BRIDGE_NAME="br-multus"
MTU=9000
VLANS="100 200"
MASTER_INTERFACE="eth1"

# Auto-detect container names (kind uses different naming than containerlab)
# Kind naming: <cluster>-control-plane, <cluster>-worker, <cluster>-worker2
# The cluster name from topology is "k01"
echo "Detecting container names..."
NODES=($(docker ps --format '{{.Names}}' | grep -E '^k01-(control-plane|worker)' | sort))

if [ ${#NODES[@]} -eq 0 ]; then
    echo "No containers found matching 'k01-*'. Trying alternative names..."
    # Try containerlab naming convention
    NODES=($(docker ps --format '{{.Names}}' | grep -E 'k01' | sort))
fi

if [ ${#NODES[@]} -eq 0 ]; then
    echo "ERROR: Could not find any Kubernetes node containers."
    echo "Please check running containers with: docker ps"
    echo ""
    echo "You can manually specify nodes by editing this script or running:"
    echo "  NODES='node1 node2 node3' ./setup-vlan-bridge.sh"
    exit 1
fi

echo "Found containers: ${NODES[*]}"
echo ""

setup_vlan_bridge() {
    local node=$1
    echo "=========================================="
    echo "Setting up VLAN-aware bridge on: $node"
    echo "=========================================="
    
    # Create VLAN-aware bridge
    docker exec "$node" bash -c "
        # Check if bridge already exists
        if ip link show $BRIDGE_NAME &>/dev/null; then
            echo 'Bridge $BRIDGE_NAME already exists, skipping creation'
        else
            echo 'Creating VLAN-aware bridge: $BRIDGE_NAME'
            ip link add name $BRIDGE_NAME type bridge vlan_filtering 1
            ip link set dev $BRIDGE_NAME mtu $MTU
            ip link set $BRIDGE_NAME up
        fi
        
        # Add master interface to bridge (if not already added)
        if ! ip link show $MASTER_INTERFACE | grep -q 'master $BRIDGE_NAME'; then
            echo 'Adding $MASTER_INTERFACE to bridge'
            ip link set $MASTER_INTERFACE master $BRIDGE_NAME
            ip link set $MASTER_INTERFACE up
            
            # Remove default VLAN 1
            bridge vlan del dev $MASTER_INTERFACE vid 1 2>/dev/null || true
        fi
        
        # Add VLANs to trunk interface
        for vlan in $VLANS; do
            echo \"Adding VLAN \$vlan to $MASTER_INTERFACE\"
            bridge vlan add dev $MASTER_INTERFACE vid \$vlan
        done
        
        # Also add VLANs to bridge interface itself (for local traffic)
        for vlan in $VLANS; do
            bridge vlan add dev $BRIDGE_NAME vid \$vlan self
        done
        
        echo ''
        echo 'Bridge VLAN configuration:'
        bridge vlan show
        echo ''
    "
}

verify_setup() {
    local node=$1
    echo ""
    echo "Verifying setup on: $node"
    echo "-------------------------------------------"
    docker exec "$node" bash -c "
        echo 'Bridge details:'
        ip -d link show $BRIDGE_NAME | head -5
        echo ''
        echo 'VLAN configuration:'
        bridge vlan show
        echo ''
        echo 'Bridge ports:'
        bridge link show
    "
}

# Main execution
echo "============================================"
echo "VLAN-Aware Bridge Setup Script"
echo "Bridge: $BRIDGE_NAME"
echo "VLANs: $VLANS"
echo "Master Interface: $MASTER_INTERFACE"
echo "============================================"
echo ""

for node in "${NODES[@]}"; do
    setup_vlan_bridge "$node"
    echo ""
done

echo ""
echo "============================================"
echo "Verification"
echo "============================================"
for node in "${NODES[@]}"; do
    verify_setup "$node"
done

echo ""
echo "============================================"
echo "Setup Complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "1. Apply the NetworkAttachmentDefinitions for VLAN 100 and 200"
echo "2. Configure the Arista switch with VLANs 100 and 200"
echo "3. Create pods using the NADs"

