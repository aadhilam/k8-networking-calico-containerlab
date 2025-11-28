#!/bin/bash
# filepath: /Users/aadhilamajeed/k824/container-labs/containerlab/calico-overlay/destroy.sh

set -e  # Exit immediately if a command exits with a non-zero status

echo "=== Destroying ContainerLab topology ==="
sudo containerlab destroy -t topology.clab.yaml || { echo "Failed to destroy topology"; exit 1; }

echo "=== Cleaning up kubeconfig ==="
rm -f k01.kubeconfig

echo "Lab destroyed successfully!"