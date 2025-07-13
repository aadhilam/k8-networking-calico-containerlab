# Calico IPAM Lab

This lab demonstrates Calico's IP Address Management (IPAM) functionality in a 3-node Kind Kubernetes cluster.

## Why IPAM is Required in Kubernetes

In Kubernetes, every pod needs a unique IP address to communicate with other pods and services. IPAM (IP Address Management) is crucial because:

**1. Dynamic Pod Creation**: Pods are ephemeral and created/destroyed frequently. Each new pod requires an available IP address from the cluster's address space.

**2. Avoiding IP Conflicts**: Without proper IPAM, multiple pods could be assigned the same IP address, causing network conflicts and communication failures.

**3. Efficient Address Allocation**: IPAM systems allocate IP addresses in blocks to nodes, reducing the overhead of individual IP requests and improving scalability.

**4. Cross-Node Communication**: Pods on different nodes need routable IP addresses within the cluster to communicate directly without NAT, which IPAM facilitates through proper subnet allocation.

<mark> Calico's IPAM provides efficient IP allocation by pre-allocating IP blocks to nodes, allowing for fast pod startup times while maintaining proper IP address management across the entire cluster. </mark>


## Lab Setup

This lab consists of:
- 3-node Kind cluster (1 control-plane, 2 workers)
- Calico CNI with IPAM enabled
- Pod CIDR: 192.168.0.0/16
- Block size: /26 (64 IPs per block)

## Deployment

The `deploy.sh` script automates the complete lab setup process:

1. **ContainerLab Topology Deployment**: Creates a 3-node Kind cluster using the `calico-ipam.clab.yaml` configuration
2. **Kubeconfig Setup**: Exports the Kind cluster's kubeconfig for kubectl access
3. **Calico Installation**: Downloads and installs calicoctl, then deploys Calico CNI components:
   - Calico Operator CRDs
   - Tigera Operator
   - Custom Calico resources with IPAM configuration
4. **Verification**: Waits for all Calico components to become available before completion

Deploy the lab using:
```bash
chmod +x deploy.sh
./deploy.sh
```

### Calico CNI Configuration

The Calico installation uses a custom Installation resource that defines the pod network configuration. Key considerations for the CIDR selection:

**Default IP Pool CIDR: 192.168.0.0/16**
- **Size**: Provides 65,536 IP addresses (sufficient for large clusters)
- **Block Size**: /26 blocks (64 IPs each) are allocated to nodes as needed
- **Avoid Conflicts**: Must not overlap with:
  - Host machine networks
  - Kubernetes service CIDR (10.96.0.0/16)
  - Any existing VPN or corporate network ranges
- **Encapsulation**: Uses VXLANCrossSubnet for pod-to-pod communication across nodes
- **NAT Outgoing**: Enabled to allow pods to reach external networks

The CIDR choice directly impacts cluster scalability and network policy effectiveness. The /16 range allows for approximately 1,024 nodes with /26 blocks, making it suitable for most lab and production environments.

## Post-Deployment Verification

After deployment, verify the cluster is ready:

### 1. Check Calico Installation Status

```bash
kubectl get tigerastatus
```

**Output Example:**
```
NAME        AVAILABLE   PROGRESSING   DEGRADED   SINCE
apiserver   True        False         False      2m30s
calico      True        False         False      2m45s
```

**Explanation:**
- **NAME**: Calico component being monitored
- **AVAILABLE**: Whether the component is fully operational
- **PROGRESSING**: Whether the component is still being deployed/updated
- **DEGRADED**: Whether the component has any issues
- **SINCE**: How long the component has been in its current state

All components should show `AVAILABLE: True` and `DEGRADED: False` for a healthy installation.

### 2. Check Node Status

```bash
kubectl get nodes
```

**Output Example:**
```
NAME                       STATUS   ROLES           AGE   VERSION
calico-ipam-control-plane  Ready    control-plane   3m    v1.28.0
calico-ipam-worker         Ready    <none>          3m    v1.28.0
calico-ipam-worker2        Ready    <none>          3m    v1.28.0
```

**Explanation:**
- **NAME**: Node name as assigned by Kind
- **STATUS**: Node readiness state (should be `Ready`)
- **ROLES**: Node role (`control-plane` for master, `<none>` for workers)
- **AGE**: How long the node has been running
- **VERSION**: Kubernetes version running on the node

All nodes should show `STATUS: Ready` indicating they are healthy and can schedule pods.

## IPAM Monitoring Commands

### 1. Overall IPAM Status

```bash
calicoctl ipam show
```

**Output Example:**
```
+----------+-------------------+------------+------------+-------------------+
| GROUPING |       CIDR        | IPS TOTAL  | IPS IN USE |    IPS FREE       |
+----------+-------------------+------------+------------+-------------------+
| IP Pool  | 192.168.0.0/16    |      65536 |         10 |             65526 |
+----------+-------------------+------------+------------+-------------------+
```

**Explanation:**
- Shows the IP pool configuration from your custom-resources.yaml
- **CIDR**: The overall pod network range (192.168.0.0/16)
- **IPS TOTAL**: Total available IP addresses in the pool (65,536)
- **IPS IN USE**: Currently allocated IP addresses to pods
- **IPS FREE**: Available IP addresses for new pod allocation

### 2. Block Affinities List

```bash
kubectl get blockaffinities
```

**Output Example:**
```
NAME                                         AGE
ipam-block-affinity-192-168-0-64-26          2m
ipam-block-affinity-192-168-1-64-26          2m
ipam-block-affinity-192-168-2-0-26           2m
```

**Explanation:**
- **BlockAffinity** resources represent IPAM block assignments to nodes
- Each entry shows which IP block is assigned to which node
- The naming convention is `ipam-block-affinity-<block-cidr-with-dashes>-<prefix-length>`
- Calico allocates /26 blocks (64 IPs each) to nodes as needed

### 3. Detailed Block Affinities

```bash
kubectl get blockaffinities -o yaml
```

**Output Example:**
```yaml
apiVersion: v1
items:
- apiVersion: crd.projectcalico.org/v1
  kind: BlockAffinity
  metadata:
    name: ipam-block-affinity-192-168-0-64-26
    namespace: ""
  spec:
    cidr: 192.168.0.64/26
    deleted: false
    node: calico-ipam-control-plane
    state: confirmed
- apiVersion: crd.projectcalico.org/v1
  kind: BlockAffinity
  metadata:
    name: ipam-block-affinity-192-168-1-64-26
  spec:
    cidr: 192.168.1.64/26
    deleted: false
    node: calico-ipam-worker
    state: confirmed
```

**Explanation:**
- **spec.cidr**: The specific IP block (e.g., 192.168.0.64/26) assigned to a node
- **spec.node**: The Kubernetes node that owns this IP block
- **spec.state**: 
  - `confirmed`: Block is actively assigned and in use
  - `pending`: Block assignment is in progress
- **spec.deleted**: Indicates if the block is marked for deletion

### 4. Formatted Block Affinities

```bash
kubectl get blockaffinities -o=jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.node}{"\t"}{.spec.cidr}{"\n"}{end}'
```

**Output Example:**
```
ipam-block-affinity-192-168-0-64-26    calico-ipam-control-plane    192.168.0.64/26
ipam-block-affinity-192-168-1-64-26    calico-ipam-worker          192.168.1.64/26
ipam-block-affinity-192-168-2-0-26     calico-ipam-worker2         192.168.2.0/26
```

**Explanation:**
- **Column 1**: BlockAffinity resource name
- **Column 2**: Node name that owns the IP block
- **Column 3**: CIDR block assigned to that node

This formatted output provides a clear mapping of which IP blocks are assigned to which nodes, making it easy to understand IP allocation across your cluster.

![Calico IPAM Architecture](../../images/calico-ipam.png)

## Key IPAM Concepts

- **IP Pools**: Large CIDR ranges (like 192.168.0.0/16) that define the overall address space
- **IP Blocks**: Smaller subnets (like /26 blocks) carved out from IP pools and assigned to nodes
- **Block Affinity**: The assignment relationship between IP blocks and nodes
- **IPAM**: Calico automatically manages IP allocation within assigned blocks when pods are created


## Troubleshooting

If you see issues with IP allocation:
1. Check if nodes have sufficient IP blocks assigned
2. Verify Calico pods are running: `kubectl get pods -n calico-system`
3. Check node status: `kubectl get nodes`
4. Review Calico logs: `kubectl logs -n calico-system -l k8s-app=calico-node`

## Lab Cleanup

When you're finished with the lab, you can clean up all resources using the automated cleanup script:

```bash
chmod +x destroy.sh
./destroy.sh
```
The destroy script will:
1. **Delete the Kind cluster** (calico-ipam) and all associated containers
2. **Destroy the ContainerLab topology** if it exists
3. **Verify cleanup** by checking for remaining containers and networks
4. **Clean up local files** like generated kubeconfig files
5. **Optionally remove Kind images** (asks for user confirmation)

### (Optional) Manual Cleanup Steps

If you prefer to clean up manually, you can run these commands individually:

### 1. Destroy the ContainerLab Topology

```bash
sudo containerlab destroy -t calico-ipam.clab.yaml
```

This command will:
- Stop and remove all containers (Kind cluster nodes)
- Remove virtual network links between containers
- Clean up the lab-specific Docker network
- Remove any ContainerLab-generated files

### 2. Verify Cleanup

Check that all lab containers have been removed:

```bash
# Verify no lab containers are running
docker ps | grep calico-ipam

# Check for any remaining ContainerLab networks
docker network ls | grep clab
```

### 3. Optional: Remove Kind Images

If you want to free up disk space, you can also remove the Kind node images:

```bash
# List Kind images
docker images | grep kindest

# Remove Kind images (optional)
docker rmi kindest/node:v1.28.0
```

### 4. Clean Up Local Files

Remove generated kubeconfig files:

```bash
rm -f calico-ipam.kubeconfig
```

**Note**: The ContainerLab destroy command is safe and will only remove resources created by this specific lab topology. It will not affect other Docker containers or networks on your system.

