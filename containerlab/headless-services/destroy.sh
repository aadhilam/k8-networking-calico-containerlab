#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

echo "=== Headless Services Lab Cleanup ==="

echo "=== Destroying ContainerLab topology ==="
sudo containerlab destroy -t headless-services.clab.yaml || { echo "Warning: Failed to destroy topology (may not exist)"; }

echo "=== Deleting Kind cluster ==="
kind delete cluster --name=headless-services || { echo "Warning: Failed to delete Kind cluster (may not exist)"; }

echo "=== Verifying cleanup ==="
echo "Checking for remaining containers..."
docker ps | grep headless-services || echo "No headless-services containers found."

echo "Checking for remaining networks..."
docker network ls | grep clab || echo "No clab networks found."

echo "=== Cleaning up local files ==="
rm -f headless-services.kubeconfig
echo "Removed kubeconfig file."

echo ""
echo "=== Cleanup Complete ==="
echo ""

read -p "Do you want to remove Kind images to free up disk space? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing Kind images..."
    docker images | grep kindest | awk '{print $3}' | xargs -r docker rmi || echo "Warning: Could not remove some images"
    echo "Kind images removed."
else
    echo "Keeping Kind images."
fi

echo ""
echo "Lab cleanup finished!"
