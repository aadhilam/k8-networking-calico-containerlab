#!/bin/bash
# filepath: /Users/aadhilamajeed/k824/container-labs/containerlab/calico-ipam/destroy.sh

set -e  # Exit immediately if a command exits with a non-zero status

echo "=== Calico IPAM Lab Cleanup Script ==="
echo ""

# Safety check: ensure we're in the correct directory
if [ ! -f "calico-ipam.clab.yaml" ]; then
    echo "Error: calico-ipam.clab.yaml not found in current directory"
    echo "Please run this script from the calico-ipam lab directory"
    exit 1
fi

echo "✓ Running from correct directory (calico-ipam lab)"
echo ""

echo "This script will destroy the following resources:"
echo "- Kind cluster: calico-ipam"
echo "- ContainerLab topology: calico-ipam"
echo "- Associated containers and networks"
echo "- Local kubeconfig file: calico-ipam.kubeconfig"
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi
echo ""

echo "=== Step 1: Delete the Kind Cluster ==="
if kind get clusters | grep -q "^calico-ipam$"; then
    echo "Deleting Kind cluster 'calico-ipam'..."
    kind delete cluster --name calico-ipam
    echo "Kind cluster deleted successfully."
else
    echo "Kind cluster 'calico-ipam' not found. Skipping..."
fi

echo ""
echo "=== Step 2: Destroy ContainerLab Topology ==="
if [ -f "calico-ipam.clab.yaml" ]; then
    echo "Destroying ContainerLab topology..."
    sudo containerlab destroy -t calico-ipam.clab.yaml || echo "ContainerLab topology may not exist or already destroyed"
else
    echo "ContainerLab topology file not found. Skipping..."
fi

echo ""
echo "=== Step 3: Verify Cleanup ==="
echo "Checking for remaining lab containers..."
# Check for Kind cluster containers (calico-ipam-*) and ContainerLab containers (clab-calico-ipam-*)
REMAINING_CONTAINERS=$(docker ps -q --filter "name=calico-ipam-" --filter "name=clab-calico-ipam-")
if [ -n "$REMAINING_CONTAINERS" ]; then
    echo "Warning: Found remaining containers:"
    docker ps --filter "name=calico-ipam-" --filter "name=clab-calico-ipam-"
else
    echo "✓ No lab containers found running"
fi

echo ""
echo "Checking for remaining ContainerLab networks..."
REMAINING_NETWORKS=$(docker network ls --filter "name=clab-calico-ipam" --format "{{.Name}}" | grep -v "^$" || true)
if [ -n "$REMAINING_NETWORKS" ]; then
    echo "Warning: Found remaining ContainerLab networks:"
    docker network ls --filter "name=clab-calico-ipam"
else
    echo "✓ No ContainerLab networks found"
fi

echo ""
echo "Checking for remaining Kind clusters..."
REMAINING_CLUSTERS=$(kind get clusters 2>/dev/null | grep "^calico-ipam$" || true)
if [ -n "$REMAINING_CLUSTERS" ]; then
    echo "Warning: Found remaining Kind clusters:"
    echo "$REMAINING_CLUSTERS"
else
    echo "✓ No lab-related Kind clusters found"
fi

echo ""
echo "=== Step 4: Clean Up Local Files ==="
echo "Removing generated kubeconfig files..."
if [ -f "calico-ipam.kubeconfig" ]; then
    rm -f calico-ipam.kubeconfig
    echo "✓ Removed calico-ipam.kubeconfig"
else
    echo "✓ No kubeconfig files to remove"
fi

echo ""
echo "=== Optional: Remove Kind Images ==="
read -p "Do you want to remove Kind node images to free up disk space? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing Kind images..."
    docker images --filter "reference=kindest/node:v1.28.0" -q | xargs -r docker rmi
    echo "✓ Kind images removed"
else
    echo "✓ Keeping Kind images"
fi

echo ""
echo "=== Cleanup Complete ==="
echo "All Calico IPAM lab resources have been cleaned up successfully!"
echo "The cleanup process only removed resources created by this specific lab."
