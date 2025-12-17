#!/bin/bash
# Cleanup script for Calico IPv6/Dual-Stack Lab

set -e

echo "=============================================="
echo "  Calico IPv6 Lab Cleanup"
echo "=============================================="
echo ""

if [ ! -f "ipv6-lab.clab.yaml" ]; then
    echo "Error: Run this script from the 14-calico-ipv6 lab directory"
    exit 1
fi

read -p "Delete the IPv6 lab? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo "=== Deleting Kind cluster ==="
kind delete cluster --name ipv6-lab 2>/dev/null || echo "Kind cluster not found"

echo "=== Destroying ContainerLab topology ==="
sudo containerlab destroy -t ipv6-lab.clab.yaml || echo "Topology already destroyed"

echo "=== Cleaning up files ==="
rm -f ipv6-lab.kubeconfig

echo ""
echo "✓ Cleanup complete!"
