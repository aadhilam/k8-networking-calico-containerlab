# IPvlan CNI Lab

## Overview

This lab demonstrates how to use IPvlan CNI with Multus to attach pods directly to a VLAN network. The lab focuses on clearly showing the differences between **MACVLAN** and **IPVLAN**, and demonstrates both **IPVLAN L2** and **IPVLAN L3** modes.

This lab shows:
- How to configure IPvlan CNI for pod networking
- The key differences between MACVLAN and IPVLAN
- IPvlan L2 mode (Layer 2) vs L3 mode (Layer 3)
- How IPvlan shares MAC addresses vs MACVLAN's unique MAC addresses
- Performance and use case differences

## Lab Topology

- **VLAN 10**: Used by Calico for pod-to-pod networking
  - Control Plane: `10.10.10.10/24`
  - Worker 1: `10.10.10.11/24`
  - Worker 2: `10.10.10.12/24`
  - Switch Gateway: `10.10.10.1/24`

- **VLAN 30**: Used for IPvlan pod attachments
  - Switch Gateway: `10.10.30.1/24`
  - IPvlan L2 Pod IP Range: `10.10.30.100-150/24`
  - IPvlan L3 Pod IP Range: `10.10.30.151-200/24`

```
                    Arista cEOS Switch
                           |
        +------------------+------------------+
        |                  |                  |
   k01-control-plane   k01-worker      k01-worker2
   eth1: VLAN 10      eth1: VLAN 10    eth1: VLAN 10
   eth2: VLAN 30      eth2: VLAN 30    eth2: VLAN 30
```

Each node has:
- `eth1`: Connected to VLAN 10 (Calico pod network)
- `eth2`: Connected to VLAN 30 (IPvlan network) - used directly as IPvlan parent interface

## Lab Setup

To setup the lab for this module **[Lab setup](../readme.md#lab-setup)**

The lab folder is - `/containerlab/22-ipvlan`

### Prerequisites

- ContainerLab installed
- Docker installed
- Arista cEOS image (`ceos:4.34.0F`) available

### Deploy the Lab

1. Navigate to the lab directory:
   ```bash
   cd containerlab/22-ipvlan
   ```

2. Run the deploy script:
   ```bash
   ./deploy.sh
   ```

   This script will:
   - Import the Arista cEOS image if needed
   - Deploy the ContainerLab topology ([topology.clab.yaml](topology.clab.yaml))
   - Install Calico CNI ([calico-cni-config/custom-resources.yaml](calico-cni-config/custom-resources.yaml))
   - Install Multus CNI
   - Install CNI plugins (including IPvlan)
   
   **Note**: You will need to manually apply the IPvlan NetworkAttachmentDefinitions ([ipvlan-l2-nad.yaml](calico-cni-config/ipvlan-l2-nad.yaml) and [ipvlan-l3-nad.yaml](calico-cni-config/ipvlan-l3-nad.yaml)) (see step 5 below)

3. Export the kubeconfig:
   ```bash
   export KUBECONFIG=$(pwd)/k01.kubeconfig
   ```

## Manifest Files

| File | Description |
|------|-------------|
| [topology.clab.yaml](topology.clab.yaml) | ContainerLab topology with Arista switch and Kind cluster |
| [k01-no-cni.yaml](k01-no-cni.yaml) | Kind cluster configuration without CNI |
| [calico-cni-config/custom-resources.yaml](calico-cni-config/custom-resources.yaml) | Custom Calico Installation resource with IPAM configuration |
| [calico-cni-config/ipvlan-l2-nad.yaml](calico-cni-config/ipvlan-l2-nad.yaml) | NetworkAttachmentDefinition for IPvlan L2 mode |
| [calico-cni-config/ipvlan-l3-nad.yaml](calico-cni-config/ipvlan-l3-nad.yaml) | NetworkAttachmentDefinition for IPvlan L3 mode |
| [tools/ipvlan-l2-pod.yaml](tools/ipvlan-l2-pod.yaml) | Pod with IPvlan L2 secondary interface |
| [tools/ipvlan-l3-pod.yaml](tools/ipvlan-l3-pod.yaml) | Pod with IPvlan L3 secondary interface |
| [tools/ipvlan-comparison-pods.yaml](tools/ipvlan-comparison-pods.yaml) | Pods for comparing IPvlan L2 vs L3 modes |

## Lab Exercises

### 1. Inspect ContainerLab Topology

First, let's inspect the lab topology defined in [topology.clab.yaml](topology.clab.yaml).

```bash
containerlab inspect topology.clab.yaml
```

### 2. Verify Kubernetes Cluster

```bash
kubectl get nodes -o wide
```

Output:

```
NAME                STATUS   ROLES           AGE   VERSION
k01-control-plane   Ready    control-plane   47m   v1.32.2
k01-worker          Ready    <none>          46m   v1.32.2
k01-worker2         Ready    <none>          46m   v1.32.2
```

### 3. Verify VLAN 30 Interface Configuration

Check that `eth2` is up and configured on each node:

```bash
docker exec -it k01-control-plane ip link show eth2
docker exec -it k01-worker ip link show eth2
docker exec -it k01-worker2 ip link show eth2
```

Output:

```
3: eth2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000
    link/ether 02:42:ac:12:00:02 brd ff:ff:ff:ff:ff:ff
```

The `eth2` interface is up and ready to be used as the parent interface for IPvlan. IPvlan will create virtual interfaces that **share the MAC address** of `eth2` but have different IP addresses.

### 4. Install and Validate Multus CNI

Multus CNI enables pods to have multiple network interfaces. We need to install it before we can use IPvlan.

#### 4.1 Install Multus CNI

```bash
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/v4.0.2/deployments/multus-daemonset.yml
```

Output:

```
namespace/kube-system created
customresourcedefinition.apiextensions.k8s.io/network-attachment-definitions.k8s.cni.cncf.io created
serviceaccount/multus-ds-amd64 created
clusterrole.rbac.authorization.k8s.io/multus-ds-amd64 created
clusterrolebinding.rbac.authorization.k8s.io/multus-ds-amd64 created
configmap/multus-cni-config created
daemonset.apps/kube-multus-ds-amd64 created
```

#### 4.2 Wait for Multus to be Ready

```bash
kubectl wait --for=condition=ready pod -l app=multus -n kube-system --timeout=120s
```

Output:

```
pod/kube-multus-ds-amd64-xxxxx condition met
pod/kube-multus-ds-amd64-yyyyy condition met
pod/kube-multus-ds-amd64-zzzzz condition met
```

#### 4.3 Verify Multus Installation

```bash
kubectl get pods -n kube-system | grep multus
```

Output:

```
kube-multus-ds-amd64-xxxxx   1/1     Running   0          30s
kube-multus-ds-amd64-yyyyy   1/1     Running   0          30s
kube-multus-ds-amd64-zzzzz   1/1     Running   0          30s
```

Multus is now installed and running as a DaemonSet on all nodes. Each Multus pod manages network attachments for pods on its respective node.

#### 4.4 View Multus Configuration

Let's examine how Multus is configured. Multus stores a template configuration in a ConfigMap, but the actual configuration that kubelet uses is in the CNI config files on each node.

First, let's check the ConfigMap (this is a template, may show default values):

```bash
kubectl get configmap multus-cni-config -n kube-system -o yaml
```

**Note**: The ConfigMap may show default/template values. The actual configuration that Multus uses is in the CNI config files on each node.

Now let's check the actual CNI configuration file that kubelet reads (this is what Multus actually uses):

```bash
docker exec k01-control-plane cat /etc/cni/net.d/00-multus.conf
```

Output:

```json
{
  "cniVersion": "0.3.1",
  "name": "multus-cni-network",
  "type": "multus",
  "capabilities": {"portMappings":true},
  "cniConf": "/host/etc/cni/multus/net.d",
  "kubeconfig": "/etc/cni/net.d/multus.d/multus.kubeconfig",
  "delegates": [
    {
      "cniVersion":"0.3.1",
      "name":"k8s-pod-network",
      "plugins":[
        {
          "container_settings":{"allow_ip_forwarding":false},
          "datastore_type":"kubernetes",
          "endpoint_status_dir":"/var/run/calico/endpoint-status",
          "ipam":{"assign_ipv4":"true","assign_ipv6":"false","type":"calico-ipam"},
          "kubernetes":{"k8s_api_root":"https://10.96.0.1:443","kubeconfig":"/etc/cni/net.d/calico-kubeconfig"},
          "log_file_max_age":30,
          "log_file_max_count":10,
          "log_file_max_size":100,
          "log_file_path":"/var/log/calico/cni/cni.log",
          "log_level":"Info",
          "mtu":0,
          "nodename_file_optional":false,
          "policy":{"type":"k8s"},
          "policy_setup_timeout_seconds":0,
          "type":"calico"
        },
        {
          "capabilities":{"portMappings":true},
          "snat":true,
          "type":"portmap"
        }
      ]
    }
  ]
}
```

This is the **actual CNI configuration file** that kubelet reads and Multus uses. Key points:

- `type: multus`: Identifies this as the Multus meta-plugin
- `delegates`: Lists the CNI plugins Multus will invoke. The first delegate contains:
  - `type: calico`: The primary CNI plugin (Calico), which creates the `eth0` interface
  - `type: portmap`: Port mapping plugin for port forwarding
- `kubeconfig`: Path to Multus's kubeconfig for accessing the Kubernetes API
- `cniConf`: Directory where Multus looks for NetworkAttachmentDefinition configurations

**Key Point**: Multus delegates to other CNI plugins. The first delegate in the list becomes the **primary CNI** (Calico), which creates the `eth0` interface. Additional networks (like IPvlan) are attached via NetworkAttachmentDefinitions based on pod annotations.

You can also list all CNI configuration files:

```bash
docker exec k01-control-plane ls -la /etc/cni/net.d/
```

Output:

```
total 28
drwx------ 1 root root 4096 Jan 16 22:23 .
drwxr-xr-x 1 root root 4096 Feb 14  2025 ..
-rw------- 1 root root 1000 Jan 16 22:23 00-multus.conf
-rw------- 1 root root  713 Jan 16 22:21 10-calico.conflist
-rw------- 1 root root 2801 Jan 16 22:22 calico-kubeconfig
drwxr-xr-x 2 root root 4096 Jan 16 22:23 multus.d
```

- `00-multus.conf`: The main Multus configuration (read first by kubelet due to numeric prefix)
- `10-calico.conflist`: Calico's CNI configuration
- `calico-kubeconfig`: Calico's kubeconfig for Kubernetes API access
- `multus.d/`: Directory containing Multus-specific configurations

**Important Question**: Why doesn't the Multus configuration show IPvlan-specific settings?

The Multus configuration uses a **two-tier configuration model**:

1. **Multus Main Configuration** (`00-multus.conf`):
   - Defines the **primary CNI** (Calico) in the `delegates` array
   - This is **always invoked** for every pod
   - Creates the `eth0` interface

2. **NetworkAttachmentDefinitions (NADs)**:
   - Secondary CNIs (like IPvlan) are configured **separately** as Kubernetes Custom Resources
   - Stored as `NetworkAttachmentDefinition` resources (not in Multus config)
   - Multus reads them **dynamically** from the Kubernetes API when pods request them via annotations

**How It Works**:
```
Pod Created with annotation:
  k8s.v1.cni.cncf.io/networks: vlan30-ipvlan-l2
    ↓
Multus reads main config → Invokes Calico (primary CNI) → Creates eth0
    ↓
Multus reads annotation → Looks up NetworkAttachmentDefinition "vlan30-ipvlan-l2"
    ↓
Multus invokes IPvlan CNI plugin → Creates net1
```

**Why This Design?**
- **Separation of concerns**: Primary CNI is always needed; secondary CNIs are optional
- **Dynamic attachment**: Pods can request different secondary networks without changing Multus config
- **Flexibility**: Multiple NADs can exist; pods choose which ones to use
- **No pod restarts**: Adding new NADs doesn't require restarting Multus

**Where IPvlan Configuration Lives**:
The IPvlan configuration is stored in the NetworkAttachmentDefinition resources (which we'll create in step 5), not in Multus's main configuration file.

#### 4.5 Install Whereabouts IPAM

Whereabouts IPAM provides cluster-wide IP allocation coordination, ensuring no IP conflicts across nodes. This is important for IPvlan where pods on different nodes need to communicate directly.

```bash
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/whereabouts/v0.9.2/doc/crds/daemonset-install.yaml
```

Output:

```
namespace/kube-system created
customresourcedefinition.apiextensions.k8s.io/ippools.whereabouts.cni.cncf.io created
customresourcedefinition.apiextensions.k8s.io/overlappingrangeipreservations.whereabouts.cni.cncf.io created
serviceaccount/whereabouts created
clusterrole.rbac.authorization.k8s.io/whereabouts created
clusterrolebinding.rbac.authorization.k8s.io/whereabouts created
daemonset.apps/whereabouts created
```

Whereabouts IPAM:
- **Cluster-wide coordination**: Tracks IP allocations across all nodes using Kubernetes CRDs
- **No IP conflicts**: Ensures each IP is allocated only once across the entire cluster
- **Better for IPvlan**: Essential when pods on different nodes need direct Layer 2/3 communication

Wait for Whereabouts to be ready:

```bash
kubectl wait --for=condition=ready pod -l app=whereabouts -n kube-system --timeout=120s
```

Output:

```
pod/whereabouts-xxxxx condition met
pod/whereabouts-yyyyy condition met
pod/whereabouts-zzzzz condition met
```

#### 4.6 Install CNI Plugins

CNI plugins (including IPvlan and whereabouts) need to be installed on each node. Let's install them:

```bash
CNI_PLUGINS_VERSION="v1.4.0"
CNI_PLUGINS_URL="https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz"

for node in k01-control-plane k01-worker k01-worker2; do
  echo "Installing CNI plugins on $node..."
  docker exec $node sh -c "curl -L ${CNI_PLUGINS_URL} | tar -C /opt/cni/bin -xz"
done
```

Output:

```
Installing CNI plugins on k01-control-plane...
Installing CNI plugins on k01-worker...
Installing CNI plugins on k01-worker2...
```

#### 4.7 Verify CNI Plugins Installation

Verify that IPvlan and whereabouts plugins are available on each node:

```bash
docker exec k01-control-plane ls -la /opt/cni/bin/ | grep ipvlan
docker exec k01-worker ls -la /opt/cni/bin/ | grep ipvlan
docker exec k01-worker2 ls -la /opt/cni/bin/ | grep ipvlan
```

Output:

```
-rwxr-xr-x 1 root root 1234567 Jan  1 00:00 ipvlan
```

The IPvlan CNI plugin is now installed on all nodes and ready to be used by Multus.

### 5. Create IPvlan NetworkAttachmentDefinitions

Before deploying pods with IPvlan interfaces, we need to create NetworkAttachmentDefinitions for both L2 and L3 modes.

#### 5.1 IPvlan L2 Mode

First, let's examine the IPvlan L2 NetworkAttachmentDefinition in [calico-cni-config/ipvlan-l2-nad.yaml](calico-cni-config/ipvlan-l2-nad.yaml):

```bash
cat calico-cni-config/ipvlan-l2-nad.yaml
```

Output:

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: vlan30-ipvlan-l2
  namespace: default
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "name": "vlan30-ipvlan-l2",
      "type": "ipvlan",
      "master": "eth2",
      "mode": "l2",
      "ipam": {
        "type": "whereabouts",
        "range": "10.10.30.100-10.10.30.150/24",
        "exclude": [
          "10.10.30.1/32"
        ],
        "gateway": "10.10.30.1"
      }
    }
```

IPvlan L2 mode:
- `type: ipvlan`: Uses IPvlan CNI plugin
- `master: eth2`: The parent physical interface
- `mode: l2`: Layer 2 mode - operates at Layer 2, similar to MACVLAN but shares MAC address
- `ipam`: Whereabouts IPAM coordinates IP allocation across all nodes
  - `type: whereabouts`: Uses whereabouts IPAM for cluster-wide IP coordination
  - `range: "10.10.30.100-10.10.30.150/24"`: IP range for allocation (cluster-wide, no conflicts)
  - `exclude: ["10.10.30.1/32"]`: Excludes gateway IP from allocation
  - `gateway: 10.10.30.1`: Gateway IP for VLAN 30

**Why Whereabouts IPAM?**
- **Cluster-wide coordination**: Ensures each IP is allocated only once across the entire cluster
- **No IP conflicts**: Pods on different nodes will never get the same IP address
- **Essential for IPvlan**: Since IPvlan provides direct Layer 2/3 connectivity, IP conflicts would cause communication issues

#### 5.2 IPvlan L3 Mode

Now examine the IPvlan L3 NetworkAttachmentDefinition in [calico-cni-config/ipvlan-l3-nad.yaml](calico-cni-config/ipvlan-l3-nad.yaml):

```bash
cat calico-cni-config/ipvlan-l3-nad.yaml
```

Output:

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: vlan30-ipvlan-l3
  namespace: default
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "name": "vlan30-ipvlan-l3",
      "type": "ipvlan",
      "master": "eth2",
      "mode": "l3",
      "ipam": {
        "type": "whereabouts",
        "range": "10.10.30.151-10.10.30.200/24",
        "exclude": [
          "10.10.30.1/32"
        ],
        "gateway": "10.10.30.1"
      }
    }
```

IPvlan L3 mode:
- `mode: l3`: Layer 3 mode - routes packets at Layer 3 without going through the switch
- `ipam`: Whereabouts IPAM coordinates IP allocation across all nodes
  - `type: whereabouts`: Uses whereabouts IPAM for cluster-wide IP coordination
  - `range: "10.10.30.151-10.10.30.200/24"`: IP range for allocation (cluster-wide, no conflicts)
  - `exclude: ["10.10.30.1/32"]`: Excludes gateway IP from allocation
  - `gateway: 10.10.30.1`: Gateway IP for VLAN 30
- Packets between pods on the same host are routed directly without switch traversal

**Why Whereabouts IPAM?**
- **Cluster-wide coordination**: Ensures each IP is allocated only once across the entire cluster
- **No IP conflicts**: Pods on different nodes will never get the same IP address
- **Essential for IPvlan L3**: Even in L3 mode, IP conflicts would cause routing issues

Now apply both NetworkAttachmentDefinitions from [ipvlan-l2-nad.yaml](calico-cni-config/ipvlan-l2-nad.yaml) and [ipvlan-l3-nad.yaml](calico-cni-config/ipvlan-l3-nad.yaml):

```bash
kubectl apply -f calico-cni-config/ipvlan-l2-nad.yaml
kubectl apply -f calico-cni-config/ipvlan-l3-nad.yaml
```

Output:

```
networkattachmentdefinition.k8s.cni.cncf.io/vlan30-ipvlan-l2 created
networkattachmentdefinition.k8s.cni.cncf.io/vlan30-ipvlan-l3 created
```

Verify the NetworkAttachmentDefinitions were created:

```bash
kubectl get network-attachment-definitions
```

**Note**: The resource name uses hyphens: `network-attachment-definitions`. You can also use the short form `kubectl get nad`.

Output:

```
NAME                AGE
vlan30-ipvlan-l2    5s
vlan30-ipvlan-l3    5s
```

### 6. Deploy Pods with IPvlan L2 Interface

> [!Important]
> Make sure you have completed step 5 and created the NetworkAttachmentDefinitions before deploying pods.

Deploy a pod with IPvlan L2 using [tools/ipvlan-l2-pod.yaml](tools/ipvlan-l2-pod.yaml):

```bash
kubectl apply -f tools/ipvlan-l2-pod.yaml
```

```bash
kubectl get pod ipvlan-l2-test-pod -o wide
```

Output:

```
NAME                READY   STATUS    RESTARTS   AGE   IP              NODE
ipvlan-l2-test-pod  1/1     Running   0          30s   192.168.0.1      k01-worker
```

### 7. Inspect IPvlan L2 Pod Network Interfaces

```bash
kubectl exec ipvlan-l2-test-pod -- ip addr show
```

Output:

```
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
3: eth0@if4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1440 qdisc noqueue state UP group default
    link/ether 02:42:c0:a8:00:01 brd ff:ff:ff:ff:ff:ff
    inet 192.168.0.1/32 scope global eth0
       valid_lft forever preferred_lft forever
4: net1@if5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 02:42:ac:12:00:02 brd ff:ff:ff:ff:ff:ff
    inet 10.10.30.100/24 scope global net1
       valid_lft forever preferred_lft forever
```

Notice the MAC address of `net1` (IPvlan interface):
- **MAC address**: `02:42:ac:12:00:02` - This is the **same MAC address as the parent interface `eth2`**
- **IP address**: `10.10.30.100/24` - Unique IP address

**Key Point**: IPvlan interfaces share the MAC address of the parent interface, unlike MACVLAN which creates unique MAC addresses.

### 8. Validate MAC Addresses and IPs on cEOS Switch

Now let's verify on the Arista cEOS switch how it sees IPvlan interfaces compared to MACVLAN. This will demonstrate the key difference: IPvlan shares MAC addresses while MACVLAN uses unique MACs.

#### 8.1 Access the cEOS Switch CLI

```bash
docker exec -it clab-ipvlan-ceos01 Cli
```

Output:

```
ceos>
```

Enter enable mode:

```bash
enable
```

Output:

```
ceos#
```

#### 8.2 Check MAC Address Table for VLAN 30

The switch should see only **one MAC address** for all IPvlan interfaces (since they share the parent's MAC), unlike MACVLAN where each interface has a unique MAC.

```bash
show mac address-table vlan 30
```

Output:

```
Mac Address Table
-------------------------------------------------------------------------------

Vlan    Mac Address       Type        Ports      Moves   Last Move
----    -----------       ----        -----      -----   ---------
  30    0242.ac12.0002    DYNAMIC     Et4        1       0:00:15 ago
```

**Key Observation**: The switch sees only **one MAC address** (`0242.ac12.0002`) for VLAN 30, even though multiple pods may be using IPvlan interfaces. This is because all IPvlan interfaces share the same MAC address as the parent interface `eth2`.

**Comparison with MACVLAN**: 
- **MACVLAN**: Switch would see multiple MAC addresses (one per pod interface)
- **IPVLAN**: Switch sees only one MAC address (shared by all pod interfaces)

#### 8.3 Generate ARP Traffic and Check ARP Table

First, let's generate some traffic from the pods to ensure the switch learns the ARP entries. From your host (not the switch), ping the switch gateway from the pods:

```bash
kubectl exec ipvlan-l2-test-pod -- ping -c 3 10.10.30.1
```

Output:

```
PING 10.10.30.1 (10.10.30.1): 56 data bytes
64 bytes from 10.10.30.1: seq=0 ttl=64 time=0.123 ms
64 bytes from 10.10.30.1: seq=1 ttl=64 time=0.098 ms
64 bytes from 10.10.30.1: seq=2 ttl=64 time=0.105 ms

--- 10.10.30.1 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss
```

If you have multiple pods, ping from another pod as well:

```bash
kubectl exec ipvlan-l3-test-pod -- ping -c 3 10.10.30.1
```

Now, back in the switch CLI, check the ARP table to see the IP-to-MAC mappings:

```bash
show arp
```

Output:

```
Address         Age (sec)  Hardware Addr    Type   Interface
10.10.10.1      00:00:00   aabb.ccdd.ee01   S      Vlan10
10.10.10.10     00:05:23   aabb.ccdd.ee10   D      Vlan10
10.10.10.11     00:05:20   aabb.ccdd.ee11   D      Vlan10
10.10.10.12     00:05:18   aabb.ccdd.ee12   D      Vlan10
10.10.30.1      00:00:00   aabb.ccdd.ee01   S      Vlan30
10.10.30.100    00:00:05   0242.ac12.0002   D      Vlan30
10.10.30.101    00:00:03   0242.ac12.0002   D      Vlan30
```

**Critical Observation**: Notice that multiple IP addresses (`10.10.30.100` and `10.10.30.101`) map to the **same MAC address** (`0242.ac12.0002`). This is the fundamental difference from MACVLAN:

- **IPVLAN**: Multiple IPs → Same MAC address
- **MACVLAN**: Each IP → Unique MAC address

The switch uses the shared MAC address to forward traffic, and the host routes packets to the correct IPvlan interface based on the destination IP address. The ping generated ARP traffic, allowing the switch to learn the pod IPs and create the ARP entries.

#### 8.4 Verify Interface Status

Check the status of the interfaces connected to VLAN 30:

```bash
show interfaces ethernet 4-6
```

Output:

```
Ethernet4 is up, line protocol is up (connected)
  Hardware is Ethernet, address is aabb.ccdd.ee04
  Description: Connection to k01-control-plane (VLAN 30)
  Internet address is not set
  Belongs to Po1
  Current address is aabb.ccdd.ee04, burned in address is aabb.ccdd.ee04
  IP MTU 1500 bytes (default), BW 10000000 kbit
  Full-duplex, 10Gb/s, auto negotiation: off
  Up 0:05:23, last link flapping: never
  Last clearing of "show interface" counters never
  5 minute input rate 0 bits/sec, 0 packets/sec
  5 minute output rate 0 bits/sec, 0 packets/sec
     0 input packets, 0 unicast packets, 0 multicast packets
     0 output packets, 0 unicast packets, 0 multicast packets
     0 input errors, 0 output errors, 0 collisions

Ethernet5 is up, line protocol is up (connected)
  Hardware is Ethernet, address is aabb.ccdd.ee05
  Description: Connection to k01-worker (VLAN 30)
  Internet address is not set
  Belongs to Po1
  Current address is aabb.ccdd.ee05, burned in address is aabb.ccdd.ee05
  IP MTU 1500 bytes (default), BW 10000000 kbit
  Full-duplex, 10Gb/s, auto negotiation: off
  Up 0:05:23, last link flapping: never
  Last clearing of "show interface" counters never
  5 minute input rate 0 bits/sec, 0 packets/sec
  5 minute output rate 0 bits/sec, 0 packets/sec
     0 input packets, 0 unicast packets, 0 multicast packets
     0 output packets, 0 unicast packets, 0 multicast packets
     0 input errors, 0 output errors, 0 collisions

Ethernet6 is up, line protocol is up (connected)
  Hardware is Ethernet, address is aabb.ccdd.ee06
  Description: Connection to k01-worker2 (VLAN 30)
  Internet address is not set
  Internet address is not set
  Belongs to Po1
  Current address is aabb.ccdd.ee06, burned in address is aabb.ccdd.ee06
  IP MTU 1500 bytes (default), BW 10000000 kbit
  Full-duplex, 10Gb/s, auto negotiation: off
  Up 0:05:23, last link flapping: never
  Last clearing of "show interface" counters never
  5 minute input rate 0 bits/sec, 0 packets/sec
  5 minute output rate 0 bits/sec, 0 packets/sec
     0 input packets, 0 unicast packets, 0 multicast packets
     0 output packets, 0 unicast packets, 0 multicast packets
     0 input errors, 0 output errors, 0 collisions
```

All interfaces are up and connected. The switch can see traffic from pods connected via IPvlan on these interfaces.

#### 8.5 Exit Switch CLI

Exit the switch CLI:

```bash
exit
```

Output:

```
ceos>
```

Then exit again to return to your shell:

```bash
exit
```

**Summary**: The switch validation demonstrates that IPvlan interfaces share MAC addresses (unlike MACVLAN), which is visible in both the MAC address table (single entry) and ARP table (multiple IPs mapping to same MAC).

### 9. Compare MAC Addresses: IPvlan vs MACVLAN

Let's check the MAC address of the parent interface on the node:

```bash
docker exec -it k01-worker ip link show eth2 | grep "link/ether"
```

Output:

```
    link/ether 02:42:ac:12:00:02 brd ff:ff:ff:ff:ff:ff
```

The IPvlan interface (`net1`) has the **exact same MAC address** (`02:42:ac:12:00:02`) as the parent interface `eth2`. This is the fundamental difference from MACVLAN.

**Comparison**:
- **MACVLAN**: Each interface gets a unique MAC address
- **IPVLAN**: All interfaces share the parent's MAC address, differentiated only by IP addresses

### 10. Deploy Pods with IPvlan L3 Interface

Deploy a pod with IPvlan L3 using [tools/ipvlan-l3-pod.yaml](tools/ipvlan-l3-pod.yaml):

```bash
kubectl apply -f tools/ipvlan-l3-pod.yaml
```

```bash
kubectl get pod ipvlan-l3-test-pod -o wide
```

Output:

```
NAME                READY   STATUS    RESTARTS   AGE   IP              NODE
ipvlan-l3-test-pod  1/1     Running   0          30s   192.168.0.2      k01-worker
```

### 11. Test IPvlan L2 vs L3 Communication

Deploy comparison pods to test both modes using [tools/ipvlan-comparison-pods.yaml](tools/ipvlan-comparison-pods.yaml):

```bash
kubectl apply -f tools/ipvlan-comparison-pods.yaml
```

Wait for all pods to be ready:

```bash
kubectl get pods -l app!=none -o wide
```

Output:

```
NAME              READY   STATUS    RESTARTS   AGE   IP              NODE
ipvlan-l2-pod-1   1/1     Running   0          30s   192.168.0.3      k01-worker
ipvlan-l2-pod-2   1/1     Running   0          30s   192.168.0.4      k01-worker2
ipvlan-l3-pod-1   1/1     Running   0          30s   192.168.0.5      k01-worker
ipvlan-l3-pod-2   1/1     Running   0          30s   192.168.0.6      k01-worker2
```

Get the IPvlan IP addresses:

```bash
kubectl exec ipvlan-l2-pod-1 -- ip addr show net1 | grep "inet "
kubectl exec ipvlan-l2-pod-2 -- ip addr show net1 | grep "inet "
kubectl exec ipvlan-l3-pod-1 -- ip addr show net1 | grep "inet "
kubectl exec ipvlan-l3-pod-2 -- ip addr show net1 | grep "inet "
```

Output:

```
inet 10.10.30.100/24 scope global net1
inet 10.10.30.101/24 scope global net1
inet 10.10.30.151/24 scope global net1
inet 10.10.30.152/24 scope global net1
```

#### 11.1 Test IPvlan L2 Communication

Test communication between L2 pods on different nodes (traffic goes through switch):

```bash
kubectl exec ipvlan-l2-pod-1 -- ping -c 3 10.10.30.101
```

Output:

```
PING 10.10.30.101 (10.10.30.101): 56 data bytes
64 bytes from 10.10.30.101: seq=0 ttl=64 time=0.456 ms
64 bytes from 10.10.30.101: seq=1 ttl=64 time=0.389 ms
64 bytes from 10.10.30.101: seq=2 ttl=64 time=0.412 ms

--- 10.10.30.101 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss
```

IPvlan L2 mode operates at Layer 2, so packets traverse the switch (similar to MACVLAN).

#### 11.2 Test IPvlan L3 Communication

Test communication between L3 pods on different nodes:

```bash
kubectl exec ipvlan-l3-pod-1 -- ping -c 3 10.10.30.152
```

Output:

```
PING 10.10.30.152 (10.10.30.152): 56 data bytes
64 bytes from 10.10.30.152: seq=0 ttl=63 time=0.234 ms
64 bytes from 10.10.30.152: seq=1 ttl=63 time=0.198 ms
64 bytes from 10.10.30.152: seq=2 ttl=63 time=0.201 ms

--- 10.10.30.152 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss
```

**Note**: Notice the TTL is 63 (not 64), indicating the packet was routed (Layer 3 operation).

#### 11.3 Test IPvlan L3 Same-Host Communication

If both L3 pods are on the same host, test communication:

```bash
# Check if pods are on same node
kubectl get pod ipvlan-l3-pod-1 ipvlan-l3-pod-2 -o wide
```

If they're on the same node, test:

```bash
kubectl exec ipvlan-l3-pod-1 -- ping -c 3 10.10.30.152
```

IPvlan L3 mode routes packets at Layer 3. If pods are on the same host, packets are routed internally without going through the switch, providing better performance.

### 12. Verify MAC Address Sharing

Verify that all IPvlan interfaces share the same MAC address:

```bash
docker exec -it k01-worker ip link show eth2 | grep "link/ether"
kubectl exec ipvlan-l2-pod-1 -- ip link show net1 | grep "link/ether"
kubectl exec ipvlan-l3-pod-1 -- ip link show net1 | grep "link/ether"
```

Output:

```
    link/ether 02:42:ac:12:00:02 brd ff:ff:ff:ff:ff:ff
    link/ether 02:42:ac:12:00:02 brd ff:ff:ff:ff:ff:ff
    link/ether 02:42:ac:12:00:02 brd ff:ff:ff:ff:ff:ff
```

All interfaces (parent `eth2` and IPvlan interfaces `net1`) share the **same MAC address**. This is the key characteristic of IPvlan.

## Additional Notes

### MACVLAN vs IPVLAN: Key Differences

#### Comparison Table

| Feature | MACVLAN | IPVLAN |
|---------|---------|--------|
| **MAC Address** | Unique MAC per interface | Shares parent's MAC address |
| **Promiscuous Mode** | Required on parent interface | Not required |
| **MAC Address Space** | Each interface has own MAC | All interfaces share MAC |
| **Switch Visibility** | Switch sees multiple MACs | Switch sees single MAC |
| **L2 Mode** | Yes (bridge, vepa, passthru, private) | Yes (Layer 2 operation) |
| **L3 Mode** | No | Yes (Layer 3 routing) |
| **Same-Host Communication** | Via switch (L2) or bridge | Via switch (L2) or direct routing (L3) |
| **Use Case** | When unique MACs needed | When MAC space is limited or L3 routing needed |

#### Detailed Differences

**1. MAC Address Handling**

**MACVLAN**:
- Creates virtual interfaces with **unique MAC addresses**
- Each pod interface has its own MAC address
- Switch sees multiple MAC addresses on the same port
- Example: Parent MAC `aa:bb:cc:dd:ee:01`, Pod1 MAC `aa:bb:cc:dd:ee:02`, Pod2 MAC `aa:bb:cc:dd:ee:03`

**IPVLAN**:
- Creates virtual interfaces that **share the parent's MAC address**
- All pod interfaces use the same MAC as the parent
- Switch sees only one MAC address on the port
- Example: Parent MAC `aa:bb:cc:dd:ee:01`, Pod1 MAC `aa:bb:cc:dd:ee:01`, Pod2 MAC `aa:bb:cc:dd:ee:01`

**2. Promiscuous Mode Requirement**

**MACVLAN**:
- Requires promiscuous mode on the parent interface
- Parent interface must accept frames not destined for its MAC
- Some cloud providers restrict promiscuous mode

**IPVLAN**:
- Does **not** require promiscuous mode
- Works in environments where promiscuous mode is restricted
- Better compatibility with cloud providers

**3. Layer 3 Mode (IPVLAN Only)**

**IPVLAN L3 Mode**:
- Routes packets at Layer 3 without switch traversal
- Pods on the same host communicate via direct routing
- Lower latency for same-host communication
- Better performance for inter-pod communication on same node

**MACVLAN**:
- No Layer 3 mode
- Always operates at Layer 2
- Same-host communication requires bridge or switch

**4. Switch Behavior**

**MACVLAN**:
- Switch learns multiple MAC addresses on the same port
- Each pod appears as a separate device to the switch
- More MAC address table entries

**IPVLAN**:
- Switch sees only one MAC address (the parent's)
- All pods appear as the same device to the switch
- Fewer MAC address table entries
- Better for MAC address space conservation

#### When to Use MACVLAN

- Applications that require unique MAC addresses
- Legacy applications that identify devices by MAC
- When you need MACVLAN's specific modes (vepa, passthru, private)
- When promiscuous mode is available and acceptable

#### When to Use IPVLAN

- MAC address space is limited
- Promiscuous mode is restricted (cloud environments)
- Need Layer 3 routing capabilities (L3 mode)
- Better performance for same-host pod communication (L3 mode)
- When MAC addresses don't matter, only IP addresses

### IPvlan L2 vs L3 Modes

#### IPvlan L2 Mode

- Operates at **Layer 2** (Ethernet)
- Similar behavior to MACVLAN bridge mode
- Packets traverse the switch for inter-pod communication
- Uses ARP for address resolution
- Suitable when you need Layer 2 connectivity

#### IPvlan L3 Mode

- Operates at **Layer 3** (IP routing)
- Routes packets internally on the host
- Same-host pod communication doesn't traverse the switch
- Lower latency for same-host communication
- Better performance for inter-pod traffic on same node
- Still uses gateway for external communication

## Summary

This lab successfully demonstrates:

### Architecture
- **Kubernetes Cluster**: 3-node Kind cluster (1 control-plane, 2 workers) running Calico CNI
- **Network Infrastructure**: Arista cEOS switch with two VLANs
- **VLAN 10**: Calico network for pod-to-pod communication
- **VLAN 30**: IPvlan network for direct Layer 2/3 pod attachments

### Key Components
- **Calico CNI**: Primary CNI for pod networking
- **Multus CNI**: Enables multiple network interfaces per pod
- **IPvlan CNI**: Provides direct Layer 2/3 connectivity to VLAN 30
- **NetworkAttachmentDefinitions**: Define IPvlan L2 and L3 configurations

### Key Learnings
- IPvlan shares MAC addresses with the parent interface (unlike MACVLAN)
- IPvlan doesn't require promiscuous mode
- IPvlan L2 mode operates at Layer 2 (similar to MACVLAN)
- IPvlan L3 mode routes packets at Layer 3 (unique to IPvlan)
- IPvlan L3 provides better performance for same-host pod communication
- IPvlan is better suited for MAC-constrained environments

### MACVLAN vs IPVLAN Summary

| Aspect | MACVLAN | IPVLAN |
|--------|---------|--------|
| MAC Addresses | Unique per interface | Shared with parent |
| Promiscuous Mode | Required | Not required |
| L3 Mode | No | Yes |
| Cloud Compatibility | Limited (promiscuous mode) | Better |
| Use Case | Unique MACs needed | MAC space limited or L3 routing needed |

This lab provides a foundation for understanding IPvlan and how it differs from MACVLAN, enabling you to choose the right technology for your specific use case.

## Lab Cleanup

To cleanup the lab follow steps in **[Lab cleanup](../readme.md#lab-cleanup)**

```bash
./destroy.sh
```
