#!/bin/bash
# Lab-specific cleanup script
# This script removes only resources created by this specific lab

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the lab directory name
LAB_DIR=$(basename "$(pwd)")

# Detect topology name from .clab.yaml file
# Try common names first, then any .clab.yaml file
TOPOLOGY_FILE=""
if [ -f "topology.clab.yaml" ]; then
    TOPOLOGY_FILE="topology.clab.yaml"
else
    TOPOLOGY_FILE=$(find . -maxdepth 1 -name "*.clab.yaml" -type f | head -1)
fi
if [ -z "$TOPOLOGY_FILE" ]; then
    echo "Error: No .clab.yaml file found in current directory"
    exit 1
fi

TOPOLOGY_NAME=$(grep "^name:" "$TOPOLOGY_FILE" | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'")
if [ -z "$TOPOLOGY_NAME" ]; then
    echo "Error: Could not detect topology name from $TOPOLOGY_FILE"
    exit 1
fi

# Detect Kind cluster name from deploy.sh
KIND_CLUSTER=$(grep "kind get kubeconfig --name=" deploy.sh 2>/dev/null | head -1 | grep -o "name=[^ ]*" | cut -d= -f2 | tr -d '>' | tr -d ' ' || echo "")
if [ -z "$KIND_CLUSTER" ]; then
    # Try to get from topology file (k8s-kind node name)
    KIND_CLUSTER=$(grep -A 5 "kind: k8s-kind" "$TOPOLOGY_FILE" | grep -E "^\s+[a-zA-Z0-9-]+:" | head -1 | awk -F: '{print $1}' | tr -d ' ' || echo "")
fi

# Detect kubeconfig filename from deploy.sh
KUBECONFIG_FILE=$(grep "\.kubeconfig" deploy.sh 2>/dev/null | head -1 | grep -o "[^ ]*\.kubeconfig" | head -1 || echo "")
if [ -z "$KUBECONFIG_FILE" ] && [ -n "$KIND_CLUSTER" ]; then
    KUBECONFIG_FILE="${KIND_CLUSTER}.kubeconfig"
fi

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Cleaning up lab: $LAB_DIR${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "Detected resources:"
echo "  Topology name: $TOPOLOGY_NAME"
echo "  Kind cluster: ${KIND_CLUSTER:-N/A}"
echo "  Kubeconfig file: ${KUBECONFIG_FILE:-N/A}"
echo ""
read -p "Continue with cleanup? (yes/no): " -r
echo ""
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Step 1: Destroy ContainerLab topology
echo -e "${GREEN}[1/5] Destroying ContainerLab topology: $TOPOLOGY_NAME${NC}"
if command -v containerlab &> /dev/null; then
    sudo containerlab destroy -t "$TOPOLOGY_FILE" 2>/dev/null || echo "  Topology may not exist or already destroyed"
else
    echo "  containerlab command not found, skipping"
fi

# Step 2: Delete Kind cluster
if [ -n "$KIND_CLUSTER" ]; then
    echo -e "${GREEN}[2/5] Deleting Kind cluster: $KIND_CLUSTER${NC}"
    if command -v kind &> /dev/null; then
        kind delete cluster --name "$KIND_CLUSTER" 2>/dev/null || echo "  Cluster may not exist or already deleted"
    else
        echo "  kind command not found, skipping"
    fi
else
    echo -e "${GREEN}[2/5] No Kind cluster detected, skipping${NC}"
fi

# Step 3: Remove lab-specific containers
echo -e "${GREEN}[3/5] Removing lab-specific containers...${NC}"
CONTAINERS=$(docker ps -a --format "{{.Names}}" 2>/dev/null | grep -E "clab-${TOPOLOGY_NAME}-|${KIND_CLUSTER}-" || true)
if [ -n "$CONTAINERS" ]; then
    echo "$CONTAINERS" | while read -r container; do
        if [ -n "$container" ]; then
            echo "  Removing container: $container"
            docker rm -f "$container" 2>/dev/null || true
        fi
    done
else
    echo "  No lab-specific containers found"
fi

# Step 4: Remove lab-specific networks
echo -e "${GREEN}[4/5] Removing lab-specific networks...${NC}"
NETWORKS=$(docker network ls --format "{{.Name}}" 2>/dev/null | grep -E "clab-${TOPOLOGY_NAME}" || true)
if [ -n "$NETWORKS" ]; then
    echo "$NETWORKS" | while read -r network; do
        if [ -n "$network" ]; then
            echo "  Removing network: $network"
            docker network rm "$network" 2>/dev/null || true
        fi
    done
else
    echo "  No lab-specific networks found"
fi

# Step 5: Clean up Kubernetes resources and kubeconfig
if [ -n "$KUBECONFIG_FILE" ] && [ -f "$KUBECONFIG_FILE" ]; then
    echo -e "${GREEN}[5/5] Cleaning up Kubernetes resources...${NC}"
    export KUBECONFIG="$(pwd)/$KUBECONFIG_FILE"
    if command -v kubectl &> /dev/null && kubectl cluster-info &>/dev/null 2>&1; then
        # Force delete stuck terminating pods
        kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded -o json 2>/dev/null | \
            jq -r '.items[] | select(.metadata.deletionTimestamp!=null) | "\(.metadata.namespace) \(.metadata.name)"' 2>/dev/null | \
            while read -r namespace name; do
                if [ -n "$namespace" ] && [ -n "$name" ]; then
                    echo "    Force deleting stuck pod: $namespace/$name"
                    kubectl delete pod "$name" -n "$namespace" --force --grace-period=0 2>/dev/null || true
                fi
            done || true
        
        # Delete lab-related namespaces (excluding system namespaces)
        kubectl get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | \
            grep -vE "^(default|kube-system|kube-public|kube-node-lease|local-path-storage)$" | \
            while read -r namespace; do
                if [ -n "$namespace" ]; then
                    echo "    Deleting namespace: $namespace"
                    kubectl delete namespace "$namespace" --timeout=30s 2>/dev/null || true
                fi
            done || true
    fi
    unset KUBECONFIG
    
    # Remove kubeconfig file
    echo "  Removing kubeconfig file: $KUBECONFIG_FILE"
    rm -f "$KUBECONFIG_FILE"
else
    echo -e "${GREEN}[5/5] No kubeconfig file found, skipping${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Cleanup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
