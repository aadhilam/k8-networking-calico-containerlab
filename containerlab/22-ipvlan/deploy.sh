#!/bin/bash
# filepath: /Users/aadhilamajeed/k824/container-labs/containerlab/22-ipvlan/deploy.sh

set -e  # Exit immediately if a command exits with a non-zero status

echo "=== Checking for Arista cEOS image ==="
if docker images ceos:4.34.0F --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -q "ceos:4.34.0F"; then
    echo "Arista cEOS image (ceos:4.34.0F) already exists, skipping import."
else
    echo "Arista cEOS image not found, importing..."
    docker import ../cEOS64-lab-4.34.0F.tar.xz ceos:4.34.0F || { echo "Failed to import cEOS image"; exit 1; }
    echo "Arista cEOS image imported successfully."
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

echo ""
echo "Kubernetes nodes:"
kubectl get nodes -o wide

echo ""
echo "=== Lab Setup Complete ==="
echo ""
echo "To use this cluster with kubectl, run:"
echo "export KUBECONFIG=$(pwd)/k01.kubeconfig"
echo ""
echo "Network Configuration:"
echo "  - VLAN 10: Calico pod network (10.10.10.0/24)"
echo "  - VLAN 30: IPvlan network (10.10.30.0/24)"
echo ""
echo "=== Next Steps ==="
echo "Before deploying pods with ipvlan, you need to:"
echo "1. Install Multus CNI (see README.md step 4)"
echo "2. Install Whereabouts IPAM (see README.md step 4.5)"
echo "3. Install CNI plugins (see README.md step 4.6)"
echo "4. Apply the ipvlan NetworkAttachmentDefinitions (see README.md step 5)"
echo "5. Then deploy test pods (see README.md step 6)"
echo ""
echo "See README.md for detailed step-by-step instructions and MACVLAN vs IPVLAN comparison."
echo ""
