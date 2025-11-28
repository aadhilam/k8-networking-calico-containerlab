#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status


echo "=== Destroying existing ContainerLab topology ==="
sudo containerlab destroy -t calico-ipam.clab.yaml || { echo "Failed to destroy existing topology"; exit 1; }

echo "=== Deploying ContainerLab topology ==="
sudo containerlab deploy -t calico-ipam.clab.yaml || { echo "Failed to deploy topology"; exit 1; }

echo "=== Waiting for Kind cluster to be ready (30 seconds) ==="
sleep 30

echo "=== Setting up kubeconfig ==="
# Create kubeconfig directory if it doesn't exist
mkdir -p ~/.kube

# Export kubeconfig to a specific file to avoid conflicts
sudo kind get kubeconfig --name=calico-ipam > calico-ipam.kubeconfig
sudo chmod 644 calico-ipam.kubeconfig

# Use the specific kubeconfig file for all kubectl commands
export KUBECONFIG=$(pwd)/calico-ipam.kubeconfig

echo "=== Installing calicoctl ==="
curl -L https://github.com/projectcalico/calico/releases/download/v3.30.0/calicoctl-linux-amd64 -o calicoctl || { echo "Failed to download calicoctl"; exit 1; }
chmod +x calicoctl
sudo mv calicoctl /usr/local/bin/ || { echo "Failed to move calicoctl to /usr/local/bin"; exit 1; }
echo "calicoctl version: $(calicoctl version)" || { echo "Warning: calicoctl may not be installed correctly"; }


echo "=== Waiting for Kubernetes API to be available ==="
until kubectl get nodes &>/dev/null; do
  echo "Waiting for Kubernetes API..."
  sleep 5
done

echo "=== Installing Calico 3.30.0 ==="
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.0/manifests/operator-crds.yaml || { echo "Failed to install Calico CRDs"; exit 1; }
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.0/manifests/tigera-operator.yaml || { echo "Failed to install Tigera operator"; exit 1; }

echo "=== Applying custom Calico resources ==="
kubectl apply -f calico-cni-config/custom-resources.yaml || { echo "Failed to apply custom resources"; exit 1; }

echo "=== Waiting for TigeraStatus to be ready ==="
echo "Initial check, expect resources to be unavailable..."
kubectl get tigerastatus

echo "Waiting for TigeraStatus to become available (may take several minutes)..."
while true; do
  # More precise check using conditions
  API_AVAILABLE=$(kubectl get tigerastatus apiserver -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "False")
  CALICO_AVAILABLE=$(kubectl get tigerastatus calico -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "False")
  
  if [[ "$API_AVAILABLE" == "True" && "$CALICO_AVAILABLE" == "True" ]]; then
    echo "Calico API server and core components are ready!"
    break
  fi
  
  echo "Still waiting for Calico components to be ready..."
  sleep 15
done

echo "=== TigeraStatus final check ==="
kubectl get tigerastatus

echo "Kubernetes nodes:"
kubectl get nodes -o wide

echo ""
echo "To use this cluster with kubectl, run:"
echo "export KUBECONFIG=$(pwd)/calico-ipam.kubeconfig"