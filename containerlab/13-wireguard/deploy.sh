#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

echo "=== Calico WireGuard Encryption Lab ==="
echo ""

echo "=== Destroying existing ContainerLab topology ==="
sudo containerlab destroy -t wireguard.clab.yaml || { echo "No existing topology to destroy"; }

echo "=== Deploying ContainerLab topology ==="
sudo containerlab deploy -t wireguard.clab.yaml || { echo "Failed to deploy topology"; exit 1; }

echo "=== Waiting for Kind cluster to be ready (30 seconds) ==="
sleep 30

echo "=== Setting up kubeconfig ==="
mkdir -p ~/.kube

sudo kind get kubeconfig --name=wireguard > wireguard.kubeconfig
sudo chmod 644 wireguard.kubeconfig

export KUBECONFIG=$(pwd)/wireguard.kubeconfig

echo "=== Installing calicoctl ==="
if ! command -v calicoctl &> /dev/null; then
    curl -L https://github.com/projectcalico/calico/releases/download/v3.30.0/calicoctl-linux-amd64 -o calicoctl || { echo "Failed to download calicoctl"; exit 1; }
    chmod +x calicoctl
    sudo mv calicoctl /usr/local/bin/ || { echo "Failed to move calicoctl to /usr/local/bin"; exit 1; }
fi
echo "calicoctl version: $(calicoctl version 2>/dev/null || echo 'installed')"

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
kubectl get tigerastatus 2>/dev/null || echo "TigeraStatus not ready yet..."

echo "Waiting for TigeraStatus to become available (may take several minutes)..."
while true; do
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

echo "=== Deploying microservices demo ==="
kubectl apply -f tools/01-backend-api.yaml
kubectl apply -f tools/02-frontend-client.yaml

echo "=== Waiting for pods to be ready ==="
kubectl wait --for=condition=ready pod/backend-api --timeout=120s
kubectl wait --for=condition=ready pod/frontend-client --timeout=120s

echo ""
echo "=== Verifying Pod Placement ==="
CLIENT_NODE=$(kubectl get pod frontend-client -o jsonpath='{.spec.nodeName}')
SERVER_NODE=$(kubectl get pod backend-api -o jsonpath='{.spec.nodeName}')

if [ "$CLIENT_NODE" == "$SERVER_NODE" ]; then
    echo ""
    echo "WARNING: Both pods are on the same node ($CLIENT_NODE)!"
    echo "WireGuard encrypts inter-node traffic only."
    echo "Consider deleting and recreating pods until they land on different nodes:"
    echo "  kubectl delete pod frontend-client backend-api"
    echo "  kubectl apply -f tools/"
    echo ""
else
    echo "Frontend ($CLIENT_NODE) and Backend ($SERVER_NODE) are on different nodes."
fi

echo ""
echo "=== Installing network tools on worker nodes ==="
docker exec wireguard-worker bash -c "apt-get update -qq && apt-get install -y -qq tcpdump wireguard-tools" > /dev/null 2>&1 && echo "Tools installed on wireguard-worker"
docker exec wireguard-worker2 bash -c "apt-get update -qq && apt-get install -y -qq tcpdump wireguard-tools" > /dev/null 2>&1 && echo "Tools installed on wireguard-worker2"

echo ""
echo "Kubernetes nodes:"
kubectl get nodes -o wide

echo ""
echo "Pods:"
kubectl get pods -o wide

echo ""
echo "=== Lab Ready ==="
echo ""
echo "To use this cluster with kubectl, run:"
echo "export KUBECONFIG=$(pwd)/wireguard.kubeconfig"
echo ""
echo "The frontend-client is continuously sending HTTP requests with sensitive data to backend-api."
echo "Current encryption status: WireGuard is DISABLED"
echo ""
echo "Quick test - capture unencrypted traffic (you'll see passwords and API keys!):"
echo "  docker exec -it wireguard-worker2 tcpdump -i eth0 -A | grep -E 'password|secret|Bearer|API-Key'"
echo ""
echo "Follow the README.md for the full lab exercises."
echo ""
  