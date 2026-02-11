#!/bin/bash
# Deploy script for Calico DSCP Lab

set -e  # Exit immediately if a command exits with a non-zero status

echo "=== Destroying existing ContainerLab topology ==="
sudo containerlab destroy -t topology.clab.yaml || { echo "Failed to destroy existing topology"; exit 1; }

echo "=== Deploying ContainerLab topology ==="
sudo containerlab deploy -t topology.clab.yaml || { echo "Failed to deploy topology"; exit 1; }

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

echo "=== Deploying sender pods ==="
kubectl apply -f k8s-manifests/sender-pod.yaml || { echo "Failed to deploy sender pods"; exit 1; }

echo "=== Waiting for pods to be ready ==="
kubectl wait --for=condition=ready pod/sender-no-dscp --timeout=120s
kubectl wait --for=condition=ready pod/sender-dscp-af11 --timeout=120s
kubectl wait --for=condition=ready pod/sender-dscp-ef --timeout=120s

echo ""
echo "=== Verifying Deployment ==="
echo ""
echo "Kubernetes nodes:"
kubectl get nodes -o wide

echo ""
echo "Sender pods:"
kubectl get pods -o wide

echo ""
echo "=== Verifying DSCP Annotations ==="
echo "sender-dscp-af11 annotations:"
kubectl get pod sender-dscp-af11 -o jsonpath='{.metadata.annotations}' | jq . 2>/dev/null || kubectl get pod sender-dscp-af11 -o jsonpath='{.metadata.annotations}'
echo ""
echo "sender-dscp-ef annotations:"
kubectl get pod sender-dscp-ef -o jsonpath='{.metadata.annotations}' | jq . 2>/dev/null || kubectl get pod sender-dscp-ef -o jsonpath='{.metadata.annotations}'

echo ""
echo "================================================================"
echo "Lab deployment completed successfully!"
echo "================================================================"
echo ""
echo "To use this cluster with kubectl, run:"
echo "export KUBECONFIG=\$(pwd)/k01.kubeconfig"
echo ""
echo "NEXT STEPS: Follow the README to test DSCP marking and throttling"
echo ""
echo "Quick test commands:"
echo "  1. Start iperf server on client:"
echo "     sudo docker exec -it clab-calico-dscp-client iperf3 -s"
echo ""
echo "  2. Test WITHOUT DSCP (no throttling):"
echo "     kubectl exec -it sender-no-dscp -- iperf3 -c 10.30.30.100 -t 10"
echo ""
echo "  3. Test WITH DSCP AF11 (throttled to 1 Mbps):"
echo "     kubectl exec -it sender-dscp-af11 -- iperf3 -c 10.30.30.100 -t 10"
echo ""
