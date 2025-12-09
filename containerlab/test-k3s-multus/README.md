# Calico and Multus Test Lab with VLAN Trunking

This lab demonstrates how to configure Calico and Multus CNI plugins in a Kubernetes cluster where nodes connect to an Arista cEOS switch via trunk ports carrying multiple VLANs.

## Lab Architecture

- **VLAN 10**: Used by Calico for pod-to-pod routing. Each node has a bridge (`br-vlan10`) with an IP address assigned.
- **VLAN 20**: Available for Multus CNI. Each node has a bridge (`br-vlan20`) without an IP address, ready for Multus network attachments.

## Topology

```
                    Arista cEOS Switch
                    (Trunk Ports)
                           |
        +------------------+------------------+
        |                  |                  |
   k01-control-plane   k01-worker      k01-worker2
   (VLAN 10 & 20)      (VLAN 10 & 20)  (VLAN 10 & 20)
```

## Network Configuration

### Switch Configuration
- All switch ports are configured as **trunk ports** carrying VLAN 10 and VLAN 20
- Native VLAN is set to VLAN 10
- VLAN 10 L3 interface: `10.10.10.1/24`
- VLAN 20 L3 interface: `10.10.20.1/24`

### Node Configuration
Each Kubernetes node has:
- **br-vlan10**: Bridge for VLAN 10 with IP address (used by Calico)
  - Control Plane: `10.10.10.10/24`
  - Worker 1: `10.10.10.11/24`
  - Worker 2: `10.10.10.12/24`
- **br-vlan20**: Bridge for VLAN 20 without IP address (for Multus)

## Lab Setup

### Prerequisites
- ContainerLab installed
- Docker installed
- Arista cEOS image (`ceos:4.34.0F`) available

### Deploy the Lab

1. Navigate to the lab directory:
   ```bash
   cd containerlab/test-k3s-multus
   ```

2. Run the deploy script:
   ```bash
   ./deploy.sh
   ```

   This script will:
   - Import the Arista cEOS image if needed
   - Deploy the ContainerLab topology
   - Wait for the Kubernetes cluster to be ready
   - Install Calico CNI
   - Install Multus CNI
   - Configure Calico to use VLAN 10 interfaces

3. Export the kubeconfig:
   ```bash
   export KUBECONFIG=$(pwd)/k01.kubeconfig
   ```

### Verify the Setup

1. **Check Kubernetes nodes:**
   ```bash
   kubectl get nodes -o wide
   ```

2. **Verify bridge and VLAN configuration on nodes:**
   ```bash
   # Check control plane node
   docker exec -it k01-control-plane ip addr show
   docker exec -it k01-control-plane ip link show br-vlan10
   docker exec -it k01-control-plane ip link show br-vlan20
   
   # Check worker nodes
   docker exec -it k01-worker ip addr show
   docker exec -it k01-worker2 ip addr show
   ```

3. **Verify Calico is using VLAN 10 interface:**
   ```bash
   kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'
   ```

4. **Check Calico node status:**
   ```bash
   kubectl get caliconodes
   calicoctl node status
   ```

5. **Verify Multus installation:**
   ```bash
   kubectl get pods -n kube-system | grep multus
   ```

## Using Multus with VLAN 20

To use Multus with VLAN 20, you'll need to create NetworkAttachmentDefinition resources. Here's an example:

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: vlan20-net
  namespace: default
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "macvlan",
      "master": "br-vlan20",
      "mode": "bridge",
      "ipam": {
        "type": "host-local",
        "subnet": "10.10.20.0/24",
        "rangeStart": "10.10.20.100",
        "rangeEnd": "10.10.20.200",
        "gateway": "10.10.20.1",
        "routes": [
          { "dst": "10.10.30.0/24", "gw": "10.10.20.1" }
        ]
      }
    }
```

Then attach this network to a pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  annotations:
    k8s.v1.cni.cncf.io/networks: vlan20-net
spec:
  containers:
  - name: test-container
    image: nicolaka/netshoot
    command: ["sleep", "3600"]
```

## Destroy the Lab

To tear down the lab:

```bash
./destroy.sh
```

## Troubleshooting

### Calico not detecting node IPs
If Calico is not detecting the correct node IPs from `br-vlan10`, you can manually configure it:

1. Check which interface Calico is using:
   ```bash
   kubectl get caliconodes -o yaml
   ```

2. Update the Installation resource to explicitly specify the interface:
   ```yaml
   nodeAddressAutodetectionV4:
     interface: "br-vlan10"
   ```

### VLAN interfaces not created
If VLAN interfaces are not being created, check:
1. The switch trunk configuration
2. The node exec commands in the topology file
3. Container logs: `docker logs k01-control-plane`

### Bridge configuration issues
To manually recreate bridges on a node:
```bash
docker exec -it k01-control-plane bash
# Then run the bridge/VLAN configuration commands manually
```

## Notes

- The topology uses `ext-container` nodes to configure bridges and VLANs before the Kubernetes cluster starts
- Calico is configured to use `br-vlan10` interfaces for pod routing
- Multus can use `br-vlan20` interfaces for additional network attachments
- BGP is configured on the switch for route advertisement (optional, can be extended)



kubectl apply -f - <<EOF
apiVersion: projectcalico.org/v3
kind: IPPool
metadata:
  name: egress-ippool-1
spec:
  cidr: 10.100.10.0/30
  blockSize: 31
  nodeSelector: "!all()"
EOF


kubectl apply -f - <<EOF
apiVersion: operator.tigera.io/v1
kind: EgressGateway
metadata:
  name: egress-gateway
  namespace: default
spec:
  logSeverity: "Info"
  replicas: 1
  ipPools:
  - cidr: "10.100.10.0/30"
  template:
    metadata:
      labels:
        egress-code: red
    spec:
      nodeSelector:
        kubernetes.io/os: linux
      terminationGracePeriodSeconds: 0
EOF

kubectl patch felixconfiguration default --type='merge' -p \
    '{"spec":{"egressIPSupport":"EnabledPerNamespaceOrPerPod"}}'

kubectl annotate deploy egress-gateway unsupported.operator.tigera.io/ignore="true"

kubectl patch deployment egress-gateway -p '
{
  "spec": {
    "template": {
      "metadata": {
        "annotations": {
          "k8s.v1.cni.cncf.io/networks": "vlan20-net, vlan100-net, vlan200-net"
        }
      }
    }
  }
}'


kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: netshoot
  namespace: default
spec:
  selector:
    matchLabels:
      app: netshoot
  template:
    metadata:
      labels:
        app: netshoot
      annotations:
        egress.projectcalico.org/selector: egress-code == 'red'
        egress.projectcalico.org/namespaceSelector: projectcalico.org/name == 'default'
    spec:
      containers:
      - name: netshoot
        image: nicolaka/netshoot
        command: ["sleep", "infinity"]
EOF