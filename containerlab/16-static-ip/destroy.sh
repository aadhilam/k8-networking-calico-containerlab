#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

echo "=== Static IP Lab Cleanup ==="

echo "=== Destroying ContainerLab topology ==="
sudo containerlab destroy -t k01.clab.yaml || { echo "Warning: Failed to destroy topology (may not exist)"; }

echo "=== Deleting Kind cluster ==="
kind delete cluster --name=k01 || { echo "Warning: Failed to delete Kind cluster (may not exist)"; }

echo "=== Verifying cleanup ==="
echo "Checking for remaining containers..."
docker ps | grep k01 || echo "No k01 containers found."

echo "Checking for remaining networks..."
docker network ls | grep clab || echo "No clab networks found."

echo "=== Cleaning up local files ==="
rm -f k01.kubeconfig
echo "Removed kubeconfig file."

echo ""
echo "=== Cleanup Complete ==="
echo ""
echo "Lab cleanup finished!"

