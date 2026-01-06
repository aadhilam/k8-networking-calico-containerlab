#!/bin/bash
# filepath: /Users/aadhilamajeed/k824/container-labs/containerlab/19-calico-ingress/deploy.sh

set -e  # Exit immediately if a command exits with a non-zero status

echo "=== Checking Arista cEOS image ==="
if docker images -q ceos:4.34.0F | grep -q .; then
    echo "cEOS image already exists, skipping import."
else
    echo "Importing Arista cEOS image..."
    docker import ../cEOS64-lab-4.34.0F.tar.xz ceos:4.34.0F || { echo "Failed to import cEOS image"; exit 1; }
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
if ! command -v calicoctl &> /dev/null; then
    curl -L https://github.com/projectcalico/calico/releases/download/v3.31.3/calicoctl-linux-amd64 -o calicoctl || { echo "Failed to download calicoctl"; exit 1; }
    chmod +x calicoctl
    sudo mv calicoctl /usr/local/bin/ || { echo "Failed to move calicoctl to /usr/local/bin"; exit 1; }
fi
echo "calicoctl version: $(calicoctl version)" || { echo "Warning: calicoctl may not be installed correctly"; }

echo "=== Waiting for Kubernetes API to be available ==="
until kubectl get nodes &>/dev/null; do
  echo "Waiting for Kubernetes API..."
  sleep 5
done

echo "=== Installing Calico 3.31.3 ==="
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.3/manifests/operator-crds.yaml || { echo "Failed to install Calico CRDs"; exit 1; }
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.3/manifests/tigera-operator.yaml || { echo "Failed to install Tigera operator"; exit 1; }

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
echo "=== Calico installation completed successfully! ==="

echo "=== Applying Calico BGP Configuration ==="
kubectl apply -f calico-cni-config/bgpconfiguration.yaml || { echo "Failed to apply BGP configuration"; exit 1; }
kubectl apply -f calico-cni-config/bgppeer.yaml || { echo "Failed to apply BGP peer"; exit 1; }

echo "=== Creating LoadBalancer IP Pool ==="
kubectl apply -f k8s-manifests/lb-ippool.yaml || { echo "Failed to create LB IP pool"; exit 1; }

echo "=== Enabling Calico Gateway API ==="
kubectl apply -f calico-cni-config/gatewayapi.yaml || { echo "Failed to enable Gateway API"; exit 1; }

echo "Waiting for Gateway API resources to be available..."
sleep 30

# Wait for GatewayClass to be created
echo "Checking for Gateway API CRDs..."
until kubectl api-resources | grep -q "gateway.networking.k8s.io"; do
  echo "Waiting for Gateway API CRDs..."
  sleep 10
done
echo "Gateway API CRDs are available!"

# Wait for tigera-gateway-class
echo "Waiting for tigera-gateway-class to be available..."
until kubectl get gatewayclass tigera-gateway-class &>/dev/null; do
  echo "Waiting for tigera-gateway-class..."
  sleep 10
done
echo "tigera-gateway-class is available!"

echo "=== Deploying Demo Applications ==="
kubectl apply -f k8s-manifests/app-v1.yaml || { echo "Failed to deploy app-v1"; exit 1; }
kubectl apply -f k8s-manifests/app-v2.yaml || { echo "Failed to deploy app-v2"; exit 1; }

echo "Waiting for application pods to be ready..."
kubectl wait --for=condition=ready pod -l app=ingress-gateway-demo -n ingress-gateway-demo --timeout=120s || { echo "Warning: Pods may not be ready yet"; }

echo ""
echo "=== Verifying Deployment ==="
echo ""
echo "Kubernetes nodes:"
kubectl get nodes -o wide

echo ""
echo "=== Verifying Node Labels ==="
echo "Nodes with bgp-peer=true label (Gateway nodes):"
kubectl get nodes -l bgp-peer=true

echo ""
echo "=== Application Pods ==="
kubectl get pods -n ingress-gateway-demo -o wide

echo ""
echo "=== GatewayClass Status ==="
kubectl get gatewayclass

echo ""
echo "================================================================"
echo "Lab infrastructure deployment completed successfully!"
echo "================================================================"
echo ""
echo "To use this cluster with kubectl, run:"
echo "export KUBECONFIG=$(pwd)/k01.kubeconfig"
echo ""
echo "NEXT STEPS: Follow the README to manually create:"
echo "  1. Gateway resource (gateway.yaml)"
echo "  2. ReferenceGrant (reference-grant.yaml)"
echo "  3. HTTPRoute (httproute.yaml)"
echo ""
echo "The manifests are located in: k8s-manifests/"
echo ""

