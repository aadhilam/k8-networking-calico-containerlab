#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

echo "=== Pod Network Lab Cleanup Script ==="
echo ""

# Safety check: ensure we're in the correct directory
if [ ! -f "k8s-dns.clab.yaml" ]; then
    echo "Error: k8s-dns.clab.yaml not found in current directory"
    echo "Please run this script from the k8s-dns lab directory"
    exit 1
fi

echo "✓ Running from correct directory (k8s-dns lab)"
echo ""

echo "This script will destroy the following resources:"
echo "- Kind cluster: k8s-dns"
echo "- ContainerLab topology: k8s-dns"
echo "- Associated containers and networks"
echo "- Local kubeconfig file: k8s-dns.kubeconfig"
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi
echo ""

echo "=== Step 1: Delete the Kind Cluster ==="
if kind get clusters | grep -q "^k8s-dns$"; then
    echo "Deleting Kind cluster 'k8s-dns'..."
    kind delete cluster --name k8s-dns
    echo "Kind cluster deleted successfully."
else
    echo "Kind cluster 'k8s-dns' not found. Skipping..."
fi

echo ""
echo "=== Step 2: Destroy ContainerLab Topology ==="
if [ -f "k8s-dns.clab.yaml" ]; then
    echo "Destroying ContainerLab topology..."
    sudo containerlab destroy -t k8s-dns.clab.yaml || echo "ContainerLab topology may not exist or already destroyed"
else
    echo "ContainerLab topology file not found. Skipping..."
fi

echo ""
echo "=== Step 3: Verify Cleanup ==="
echo "Checking for remaining lab containers..."
# Check for Kind cluster containers (k8s-dns-*) and ContainerLab containers (clab-k8s-dns-*)
REMAINING_CONTAINERS=$(docker ps -q --filter "name=k8s-dns-" --filter "name=clab-k8s-dns-")
if [ -n "$REMAINING_CONTAINERS" ]; then
    echo "Warning: Found remaining containers:"
    docker ps --filter "name=k8s-dns-" --filter "name=clab-k8s-dns-"
else
    echo "✓ No lab containers found running"
fi

echo ""
echo "Checking for remaining ContainerLab networks..."
REMAINING_NETWORKS=$(docker network ls --filter "name=clab-k8s-dns" --format "{{.Name}}" | grep -v "^$" || true)
if [ -n "$REMAINING_NETWORKS" ]; then
    echo "Warning: Found remaining ContainerLab networks:"
    docker network ls --filter "name=clab-k8s-dns"
else
    echo "✓ No ContainerLab networks found"
fi

echo ""
echo "Checking for remaining Kind clusters..."
REMAINING_CLUSTERS=$(kind get clusters 2>/dev/null | grep "^k8s-dns$" || true)
if [ -n "$REMAINING_CLUSTERS" ]; then
    echo "Warning: Found remaining Kind clusters:"
    echo "$REMAINING_CLUSTERS"
else
    echo "✓ No lab-related Kind clusters found"
fi

echo ""
echo "=== Step 4: Clean Up Local Files ==="
echo "Removing generated kubeconfig files..."
if [ -f "k8s-dns.kubeconfig" ]; then
    rm -f k8s-dns.kubeconfig
    echo "✓ Removed k8s-dns.kubeconfig"
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
echo "All Pod Network lab resources have been cleaned up successfully!"
echo "The cleanup process only removed resources created by this specific lab."
