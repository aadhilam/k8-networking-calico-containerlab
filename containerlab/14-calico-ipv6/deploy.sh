#!/bin/bash
# Deployment script for Calico IPv6/Dual-Stack Lab

set -e

echo "=============================================="
echo "  Calico IPv6/Dual-Stack Lab Deployment"
echo "=============================================="
echo ""

echo "=== Destroying existing ContainerLab topology ==="
sudo containerlab destroy -t ipv6-lab.clab.yaml || echo "No existing topology to destroy"

echo "=== Deploying ContainerLab topology ==="
sudo containerlab deploy -t ipv6-lab.clab.yaml || { echo "Failed to deploy topology"; exit 1; }

echo "=== Waiting for Kind cluster to be ready (30 seconds) ==="
sleep 30

echo "=== Setting up kubeconfig ==="
mkdir -p ~/.kube
sudo kind get kubeconfig --name=ipv6-lab > ipv6-lab.kubeconfig
sudo chmod 644 ipv6-lab.kubeconfig
export KUBECONFIG=$(pwd)/ipv6-lab.kubeconfig

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
echo "  export KUBECONFIG=$(pwd)/ipv6-lab.kubeconfig"
echo ""
echo "Verify IPv6 pod addresses:"
echo "  kubectl get pods -o wide"
echo ""
echo "Check IP pools:"
echo "  calicoctl get ippools -o wide"
echo ""
