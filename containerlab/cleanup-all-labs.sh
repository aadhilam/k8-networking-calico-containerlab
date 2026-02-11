#!/bin/bash
# Comprehensive cleanup script for all container-labs
# This script removes ALL lab remnants: Kind clusters, ContainerLab topologies,
# Docker containers/networks, Kubernetes resources, network interfaces, and kubeconfig files

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Container Labs Complete Cleanup${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "This script will remove:"
echo "  - All Kind clusters"
echo "  - All ContainerLab topologies"
echo "  - All lab-related Docker containers"
echo "  - All lab-related Docker images"
echo "  - All lab-related Docker networks"
echo "  - All lab-related Kubernetes namespaces"
echo "  - All kubeconfig files"
echo "  - Lab-created network interfaces"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
echo ""
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo -e "${GREEN}[1/8] Cleaning up Kind clusters...${NC}"
if command -v kind &> /dev/null; then
    CLUSTERS=$(kind get clusters 2>/dev/null || echo "")
    if [ -n "$CLUSTERS" ]; then
        echo "$CLUSTERS" | while read -r cluster; do
            if [ -n "$cluster" ]; then
                echo "  Deleting Kind cluster: $cluster"
                kind delete cluster --name "$cluster" 2>/dev/null || true
            fi
        done
    else
        echo "  No Kind clusters found"
    fi
else
    echo "  kind command not found, skipping"
fi

echo -e "${GREEN}[2/8] Cleaning up ContainerLab topologies...${NC}"
if command -v containerlab &> /dev/null; then
    # Find all .clab.yaml files and destroy their topologies
    find . -name "*.clab.yaml" -type f 2>/dev/null | while read -r topo_file; do
        topo_name=$(basename "$topo_file" .clab.yaml)
        echo "  Destroying topology: $topo_name"
        sudo containerlab destroy -t "$topo_file" 2>/dev/null || true
    done
    
    # Also try to destroy by name patterns
    sudo containerlab destroy --all 2>/dev/null || true
else
    echo "  containerlab command not found, skipping"
fi

echo -e "${GREEN}[3/8] Cleaning up Docker containers...${NC}"
# Remove all containers with lab-related names
CONTAINERS=$(docker ps -a --format "{{.Names}}" 2>/dev/null | grep -E "(clab-|k01-|calico-|kind-|pod-routing|pod-network|k8-services|k8s-dns|headless-services|calico-qos|wireguard|dual-stack|macvlan|ipvlan|mtu-lab|test-k3s)" || true)
if [ -n "$CONTAINERS" ]; then
    echo "$CONTAINERS" | while read -r container; do
        if [ -n "$container" ]; then
            echo "  Removing container: $container"
            docker rm -f "$container" 2>/dev/null || true
        fi
    done
else
    echo "  No lab containers found"
fi

echo -e "${GREEN}[4/9] Cleaning up Docker images...${NC}"
# Remove lab-related Docker images
IMAGES=$(docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -E "(ceos:|kindest/node:|calico|clab-|containerlab)" || true)
if [ -n "$IMAGES" ]; then
    echo "$IMAGES" | while read -r image; do
        if [ -n "$image" ]; then
            echo "  Removing image: $image"
            docker rmi -f "$image" 2>/dev/null || true
        fi
    done
else
    echo "  No lab images found"
fi

# Also remove dangling images that might be from labs
echo "  Removing dangling images..."
docker image prune -f 2>/dev/null || true

echo -e "${GREEN}[5/9] Cleaning up Docker networks...${NC}"
# Remove all non-default networks
NETWORKS=$(docker network ls --format "{{.Name}}" 2>/dev/null | grep -vE "^(bridge|host|none)$" || true)
if [ -n "$NETWORKS" ]; then
    echo "$NETWORKS" | while read -r network; do
        if [ -n "$network" ]; then
            echo "  Removing network: $network"
            docker network rm "$network" 2>/dev/null || true
        fi
    done
else
    echo "  No custom networks found"
fi

echo -e "${GREEN}[6/9] Cleaning up Kubernetes resources...${NC}"
# Try to clean up namespaces if kubectl is available and we have a valid context
if command -v kubectl &> /dev/null; then
    # Get all kubeconfig files and try to clean up resources
    find . -name "*.kubeconfig" -type f 2>/dev/null | while read -r kubeconfig; do
        export KUBECONFIG="$kubeconfig"
        if kubectl cluster-info &>/dev/null; then
            echo "  Cleaning up resources using: $kubeconfig"
            
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
    done
    unset KUBECONFIG
else
    echo "  kubectl not found, skipping Kubernetes cleanup"
fi

echo -e "${GREEN}[7/9] Cleaning up network interfaces...${NC}"
# Remove veth pairs and bridges created by labs
# Note: This requires sudo and may affect other network interfaces
if [ "$EUID" -eq 0 ] || sudo -n true 2>/dev/null; then
    # Remove veth pairs (usually created by CNI plugins)
    ip link show 2>/dev/null | grep -E "^[0-9]+: veth" | awk -F: '{print $2}' | awk '{print $1}' | \
        while read -r iface; do
            if [ -n "$iface" ]; then
                echo "  Removing veth interface: $iface"
                sudo ip link delete "$iface" 2>/dev/null || true
            fi
        done || true
    
    # Remove cali* interfaces (Calico interfaces)
    ip link show 2>/dev/null | grep -E "^[0-9]+: cali" | awk -F: '{print $2}' | awk '{print $1}' | \
        while read -r iface; do
            if [ -n "$iface" ]; then
                echo "  Removing Calico interface: $iface"
                sudo ip link delete "$iface" 2>/dev/null || true
            fi
        done || true
    
    # Remove lab-created bridges
    ip link show type bridge 2>/dev/null | grep -E "^[0-9]+: (br-|docker|kind)" | awk -F: '{print $2}' | awk '{print $1}' | \
        while read -r bridge; do
            if [ -n "$bridge" ] && [ "$bridge" != "docker0" ]; then
                echo "  Removing bridge: $bridge"
                sudo ip link set "$bridge" down 2>/dev/null || true
                sudo brctl delbr "$bridge" 2>/dev/null || true
            fi
        done || true
else
    echo "  Skipping network interface cleanup (requires sudo)"
fi

echo -e "${GREEN}[8/9] Cleaning up kubeconfig files...${NC}"
KUBECONFIGS=$(find . -name "*.kubeconfig" -type f 2>/dev/null || true)
if [ -n "$KUBECONFIGS" ]; then
    echo "$KUBECONFIGS" | while read -r kubeconfig; do
        if [ -n "$kubeconfig" ]; then
            echo "  Removing kubeconfig: $kubeconfig"
            rm -f "$kubeconfig"
        fi
    done
else
    echo "  No kubeconfig files found"
fi

echo -e "${GREEN}[9/9] Final Docker cleanup...${NC}"
# Remove any remaining stopped containers
STOPPED=$(docker ps -a -q --filter "status=exited" 2>/dev/null || true)
if [ -n "$STOPPED" ]; then
    echo "  Removing stopped containers..."
    docker rm $STOPPED 2>/dev/null || true
fi

# Prune unused resources
echo "  Pruning unused Docker resources..."
docker system prune -f --volumes 2>/dev/null || true

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Cleanup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Remaining resources check:"
echo "  Kind clusters: $(kind get clusters 2>/dev/null | wc -l | tr -d ' ' || echo '0')"
echo "  Docker containers: $(docker ps -a --format "{{.Names}}" 2>/dev/null | grep -E "(clab-|k01-|calico-|kind-)" | wc -l | tr -d ' ' || echo '0')"
echo "  Docker images: $(docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -E "(ceos:|kindest/node:|calico|clab-)" | wc -l | tr -d ' ' || echo '0')"
echo "  Docker networks: $(docker network ls --format "{{.Name}}" 2>/dev/null | grep -vE "^(bridge|host|none)$" | wc -l | tr -d ' ' || echo '0')"
echo "  Kubeconfig files: $(find . -name "*.kubeconfig" -type f 2>/dev/null | wc -l | tr -d ' ' || echo '0')"
echo ""
