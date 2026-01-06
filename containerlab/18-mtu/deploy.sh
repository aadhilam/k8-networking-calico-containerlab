#!/bin/bash
# filepath: /Users/aadhilamajeed/k824/container-labs/containerlab/18-mtu/deploy.sh

set -e  # Exit immediately if a command exits with a non-zero status

echo "=== MTU Lab ==="
echo ""
echo "This lab demonstrates MTU configuration in Kubernetes with Calico"
echo ""

echo "=== Checking Arista cEOS image ==="
if docker image inspect ceos:4.34.0F &>/dev/null; then
    echo "cEOS image already exists, skipping import"
else
    echo "Importing Arista cEOS image..."
    docker import ../cEOS64-lab-4.34.0F.tar.xz ceos:4.34.0F || { echo "Failed to import cEOS image"; exit 1; }
fi

echo "=== Destroying existing ContainerLab topology ==="
sudo containerlab destroy -t topology.clab.yaml || { echo "No existing topology to destroy"; }

echo "=== Deploying ContainerLab topology ==="
sudo containerlab deploy -t topology.clab.yaml || { echo "Failed to deploy topology"; exit 1; }

echo "=== Waiting for Kind cluster to be ready (30 seconds) ==="
sleep 30

echo "=== Setting up kubeconfig ==="
mkdir -p ~/.kube

sudo kind get kubeconfig --name=k01 > mtu-lab.kubeconfig
sudo chmod 644 mtu-lab.kubeconfig

export KUBECONFIG=$(pwd)/mtu-lab.kubeconfig

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

echo "=== Applying custom Calico resources (default MTU - 1450) ==="
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

echo "=== Setting host interface MTU to 9000 (jumbo frames) ==="
docker exec k01-control-plane ip link set eth1 mtu 9000 || echo "Warning: Could not set MTU on control-plane"
docker exec k01-worker ip link set eth1 mtu 9000 || echo "Warning: Could not set MTU on worker"
docker exec k01-worker2 ip link set eth1 mtu 9000 || echo "Warning: Could not set MTU on worker2"
docker exec k01-worker3 ip link set eth1 mtu 9000 || echo "Warning: Could not set MTU on worker3"

echo "=== Installing network tools (ping, tcpdump) on all nodes ==="
docker exec k01-control-plane bash -c "apt-get update -qq && apt-get install -y -qq iputils-ping tcpdump" > /dev/null 2>&1 && echo "Tools installed on k01-control-plane"
docker exec k01-worker bash -c "apt-get update -qq && apt-get install -y -qq iputils-ping tcpdump" > /dev/null 2>&1 && echo "Tools installed on k01-worker"
docker exec k01-worker2 bash -c "apt-get update -qq && apt-get install -y -qq iputils-ping tcpdump" > /dev/null 2>&1 && echo "Tools installed on k01-worker2"
docker exec k01-worker3 bash -c "apt-get update -qq && apt-get install -y -qq iputils-ping tcpdump" > /dev/null 2>&1 && echo "Tools installed on k01-worker3"

echo "=== Deploying netshoot pods ==="
kubectl apply -f tools/01-netshoot-server.yaml
kubectl apply -f tools/02-netshoot-client.yaml

echo "=== Waiting for pods to be ready ==="
kubectl wait --for=condition=ready pod/netshoot-server --timeout=120s
kubectl wait --for=condition=ready pod/netshoot-client --timeout=120s

echo ""
echo "=== Verifying Pod Placement ==="
CLIENT_NODE=$(kubectl get pod netshoot-client -o jsonpath='{.spec.nodeName}')
SERVER_NODE=$(kubectl get pod netshoot-server -o jsonpath='{.spec.nodeName}')
echo "Netshoot Client is on: $CLIENT_NODE"
echo "Netshoot Server is on: $SERVER_NODE"

echo ""
echo "=== Kubernetes nodes ==="
kubectl get nodes -o wide

echo ""
echo "=== Pods ==="
kubectl get pods -o wide

echo ""
echo "=== Current Configuration ==="
echo ""
echo "Switch VLAN interfaces: 9000 bytes (jumbo frames)"
echo "Host interfaces (eth1): 9000 bytes"
echo "Calico pod interface MTU: 1450 bytes (DEFAULT - not configured)"
echo ""

echo "=== Lab Ready ==="
echo ""
echo "To use this cluster with kubectl, run:"
echo "export KUBECONFIG=$(pwd)/mtu-lab.kubeconfig"
echo ""
echo "Follow the README.md for the lab exercises."
echo ""
