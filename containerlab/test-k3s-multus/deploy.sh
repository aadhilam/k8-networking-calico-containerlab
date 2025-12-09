#!/bin/bash
# Deploy script for Calico and Multus test lab

set -e  # Exit immediately if a command exits with a non-zero status

echo "=== Checking for Arista cEOS image ==="
if ! docker image inspect ceos:4.34.0F &>/dev/null; then
    echo "Image not found. Importing Arista cEOS image..."
    docker import ../cEOS64-lab-4.34.0F.tar.xz ceos:4.34.0F || { echo "Failed to import cEOS image"; exit 1; }
else
    echo "Arista cEOS image already exists. Skipping import."
fi

echo "=== Destroying existing ContainerLab topology ==="
sudo containerlab destroy -t topology.clab.yaml || { echo "Failed to destroy existing topology"; exit 1; }

echo "=== Deploying ContainerLab topology ==="
sudo containerlab deploy -t topology.clab.yaml || { echo "Failed to deploy topology"; exit 1; }

echo "=== Waiting for Kind cluster to be ready (30 seconds) ==="
sleep 30

echo "=== Setting up kubeconfig ==="
# Create kubeconfig directory if it doesn't exist
mkdir -p ~/.kube

# Export kubeconfig to a specific file to avoid conflicts
sudo kind get kubeconfig --name=k01 > k01.kubeconfig
sudo chmod 644 k01.kubeconfig

# Use the specific kubeconfig file for all kubectl commands
export KUBECONFIG=$(pwd)/k01.kubeconfig

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
if [ -f "calico-cni-config/custom-resources.yaml" ]; then
    kubectl apply -f calico-cni-config/custom-resources.yaml || { echo "Failed to apply custom resources"; exit 1; }
else
    echo "Warning: calico-cni-config/custom-resources.yaml not found. Skipping custom resources."
fi

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
echo "=== Calico installation completed successfully! ==="

echo ""
echo "=== Installing Multus CNI ==="
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/v4.0.2/deployments/multus-daemonset.yml || { echo "Failed to install Multus"; exit 1; }

echo "=== Waiting for Multus to be ready ==="
kubectl wait --for=condition=ready pod -l app=multus -n kube-system --timeout=120s || { echo "Warning: Multus pods may not be ready"; }

echo ""
echo "=== Installing CNI plugins on all nodes ==="
CNI_PLUGINS_VERSION="v1.4.0"
CNI_PLUGINS_URL="https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz"

for node in k01-control-plane k01-worker k01-worker2; do
  echo "Installing CNI plugins on $node..."
  docker exec $node sh -c "curl -L ${CNI_PLUGINS_URL} | tar -C /opt/cni/bin -xz" || { echo "Failed to install CNI plugins on $node"; exit 1; }
done
echo "=== CNI plugins installation completed ==="

echo ""
echo "Kubernetes nodes:"
kubectl get nodes -o wide

echo ""
echo "=== Lab Setup Complete ==="
echo ""
echo "Network Configuration:"
echo "  - VLAN 10 (br-trunk.10): Used by Calico for pod networking"
echo "    - Control Plane: 10.10.10.10/24"
echo "    - Worker 1: 10.10.10.11/24"
echo "    - Worker 2: 10.10.10.12/24"
echo ""
echo "  - VLAN 20 (br-trunk.20): Available for Multus"
echo "    - Switch IP: 10.10.20.1/24"
echo ""
echo "To use this cluster with kubectl, run:"
echo "export KUBECONFIG=$(pwd)/k01.kubeconfig"
echo ""
echo "To verify bridge and VLAN configuration on nodes:"
echo "  docker exec -it k01-control-plane ip addr show"
echo "  docker exec -it k01-control-plane ip link show br-trunk"
echo ""

