#!/bin/bash
# Deployment script for Calico Dual-Stack Lab
# Demonstrates pods reaching both IPv4 and IPv6 external destinations

set -e

echo "=============================================="
echo "  Calico Dual-Stack Lab Deployment"
echo "=============================================="
echo ""

echo "=== Checking Arista cEOS image ==="
if docker image inspect ceos:4.34.0F &>/dev/null; then
    echo "cEOS image already exists, skipping import"
else
    echo "Importing Arista cEOS image..."
    docker import ../cEOS64-lab-4.34.0F.tar.xz ceos:4.34.0F || { echo "Failed to import cEOS image"; exit 1; }
fi

echo "=== Destroying existing ContainerLab topology ==="
sudo containerlab destroy -t topology.clab.yaml || echo "No existing topology to destroy"

echo "=== Deploying ContainerLab topology ==="
sudo containerlab deploy -t topology.clab.yaml || { echo "Failed to deploy topology"; exit 1; }

echo "=== Waiting for Kind cluster to be ready (30 seconds) ==="
sleep 30

echo "=== Setting up kubeconfig ==="
mkdir -p ~/.kube
sudo kind get kubeconfig --name=dual-stack > dual-stack.kubeconfig
sudo chmod 644 dual-stack.kubeconfig
export KUBECONFIG=$(pwd)/dual-stack.kubeconfig

echo "=== Installing calicoctl ==="
if ! command -v calicoctl &> /dev/null; then
    curl -L https://github.com/projectcalico/calico/releases/download/v3.30.0/calicoctl-linux-amd64 -o calicoctl
    chmod +x calicoctl
    sudo mv calicoctl /usr/local/bin/
fi

echo "=== Waiting for Kubernetes API ==="
until kubectl get nodes &>/dev/null; do
  echo "Waiting for Kubernetes API..."
  sleep 5
done

echo "=== Installing Calico 3.30.0 ==="
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.0/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.0/manifests/tigera-operator.yaml

echo "=== Applying Calico dual-stack configuration ==="
kubectl apply -f calico-cni-config/custom-resources.yaml

echo "=== Waiting for Calico to be ready ==="
while true; do
  API_AVAILABLE=$(kubectl get tigerastatus apiserver -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "False")
  CALICO_AVAILABLE=$(kubectl get tigerastatus calico -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "False")
  
  if [[ "$API_AVAILABLE" == "True" && "$CALICO_AVAILABLE" == "True" ]]; then
    echo "Calico is ready!"
    break
  fi
  echo "Waiting for Calico..."
  sleep 15
done

echo "=== Deploying test pods ==="
kubectl apply -f tools/multitool-pod.yaml
kubectl wait --for=condition=Ready pod -l app=multitool --timeout=120s || echo "Warning: Some pods may not be ready yet"

echo ""
echo "=============================================="
echo "  Deployment Complete!"
echo "=============================================="
echo ""
echo "To use this cluster:"
echo "  export KUBECONFIG=$(pwd)/dual-stack.kubeconfig"
echo ""
echo "Verify dual-stack pod addresses:"
echo "  calicoctl get workloadendpoints -o wide"
echo ""
echo "Test external IPv4 connectivity (cEOS loopback):"
echo "  kubectl exec -it \$(kubectl get pods -l app=multitool -o name | head -1) -- ping -c 3 1.1.1.1"
echo ""
echo "Test external IPv6 connectivity (cEOS loopback):"
echo "  kubectl exec -it \$(kubectl get pods -l app=multitool -o name | head -1) -- ping6 -c 3 2001:db8::1"
echo ""
