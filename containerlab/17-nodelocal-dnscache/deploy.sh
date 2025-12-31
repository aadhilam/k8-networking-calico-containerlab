#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

echo "=== Destroying existing ContainerLab topology ==="
sudo containerlab destroy -t k01.clab.yaml || { echo "No existing topology to destroy"; }

echo "=== Deploying ContainerLab topology ==="
sudo containerlab deploy -t k01.clab.yaml || { echo "Failed to deploy topology"; exit 1; }

echo "=== Waiting for Kind cluster to be ready (30 seconds) ==="
sleep 30

echo "=== Setting up kubeconfig ==="
mkdir -p ~/.kube

sudo kind get kubeconfig --name=k01 > k01.kubeconfig
sudo chmod 644 k01.kubeconfig

export KUBECONFIG=$(pwd)/k01.kubeconfig

echo "=== Waiting for Kubernetes API to be available ==="
until kubectl get nodes &>/dev/null; do
  echo "Waiting for Kubernetes API..."
  sleep 5
done

echo "=== Installing Calico 3.30.0 ==="
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.0/manifests/operator-crds.yaml || { echo "Failed to install Calico CRDs"; exit 1; }
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.0/manifests/tigera-operator.yaml || { echo "Failed to install Tigera operator"; exit 1; }

echo "=== Waiting for Tigera operator to be ready ==="
kubectl wait --for=condition=available --timeout=120s deployment/tigera-operator -n tigera-operator

echo "=== Waiting for CRDs to be established ==="
sleep 10

echo "=== Applying Calico Installation resource ==="
kubectl apply -f calico-cni-config/custom-resources.yaml || { echo "Failed to apply custom resources"; exit 1; }

echo "=== Waiting for Calico to be ready ==="
echo "Waiting for Calico pods to be ready (may take several minutes)..."
sleep 30

while true; do
  CALICO_READY=$(kubectl get pods -n calico-system -l k8s-app=calico-node --no-headers 2>/dev/null | grep -c "Running" || echo "0")
  NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
  
  if [[ "$CALICO_READY" -ge "$NODE_COUNT" ]]; then
    echo "Calico nodes are ready!"
    break
  fi
  
  echo "Still waiting for Calico to be ready ($CALICO_READY/$NODE_COUNT nodes ready)..."
  sleep 10
done

echo "=== Deploying DNS test pod ==="
kubectl apply -f tools/dns-test-pod.yaml

echo "=== Waiting for DNS test pod to be ready ==="
kubectl wait --for=condition=ready pod/dns-test --timeout=120s

echo ""
echo "=== Cluster Status ==="
echo "Kubernetes nodes:"
kubectl get nodes -o wide

echo ""
echo "CoreDNS pods:"
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide

echo ""
echo "DNS test pod:"
kubectl get pods dns-test -o wide

echo ""
echo "=== Lab Ready ==="
echo "To use this cluster with kubectl, run:"
echo "export KUBECONFIG=$(pwd)/k01.kubeconfig"
echo ""
echo "Follow the README.md for the lab exercises."

