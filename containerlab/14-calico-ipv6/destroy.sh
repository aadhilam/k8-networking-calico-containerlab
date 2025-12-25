#!/bin/bash
# Cleanup script for Calico Dual-Stack Lab

set -e

echo "=============================================="
echo "  Calico Dual-Stack Lab Cleanup"
echo "=============================================="
echo ""

if [ ! -f "topology.clab.yaml" ]; then
    echo "Error: Run this script from the 14-calico-ipv6 lab directory"
    exit 1
fi

read -p "Delete the dual-stack lab? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo "=== Deleting Kind cluster ==="
kind delete cluster --name dual-stack 2>/dev/null || echo "Kind cluster not found"

echo "=== Destroying ContainerLab topology ==="
sudo containerlab destroy -t topology.clab.yaml || echo "Topology already destroyed"

echo "=== Cleaning up files ==="
rm -f dual-stack.kubeconfig

echo ""
echo "✓ Cleanup complete!"
