# Calico Advertise IPPool Using BGP

This lab demonstrates how to advertise Calico IP pools to external networks using BGP. You will learn how to configure BGP peering between Calico nodes and an upstream router to make pod IP addresses routable outside the Kubernetes cluster.

## Lab Setup
To setup the lab for this module **[Lab setup](../readme.md#lab-setup)**
The lab folder is - `/containerlab/10-multi-ippool`




## Lab

### 1. Inspect ContainerLab Topology

First, let's inspect the lab topology.

##### command
```bash
containerlab inspect topology.clab.yaml 
```
```
16:05:41 INFO Parsing & checking topology file=topology.clab.yaml
╭───────────────────────────┬──────────────────┬─────────┬───────────────────────╮
│            Name           │   Kind/Image     │  State  │     IPv4/6 Address    │
├───────────────────────────┼──────────────────┼─────────┼───────────────────────┤
│ k01-control-plane         │ ext-container    │ running │ 172.18.0.4            │
│                           │ kindest/node     │         │ fc00:f853:ccd:e793::4 │
├───────────────────────────┼──────────────────┼─────────┼───────────────────────┤
│ k01-worker                │ ext-container    │ running │ 172.18.0.5            │
│                           │ kindest/node     │         │ fc00:f853:ccd:e793::5 │
├───────────────────────────┼──────────────────┼─────────┼───────────────────────┤
│ k01-worker2               │ ext-container    │ running │ 172.18.0.2            │
│                           │ kindest/node     │         │ fc00:f853:ccd:e793::2 │
├───────────────────────────┼──────────────────┼─────────┼───────────────────────┤
│ k01-worker3               │ ext-container    │ running │ 172.18.0.3            │
│                           │ kindest/node     │         │ fc00:f853:ccd:e793::3 │
├───────────────────────────┼──────────────────┼─────────┼───────────────────────┤
│ clab-calico-bgp-lb-ceos01 │ arista_ceos      │ running │ 172.20.20.2           │
│                           │ ceos:4.34.0F     │         │ 3fff:172:20:20::2     │
├───────────────────────────┼──────────────────┼─────────┼───────────────────────┤
│ k01-control-plane         │ k8s-kind         │ running │ 172.18.0.4            │
│                           │ kindest/node     │         │ fc00:f853:ccd:e793::4 │
├───────────────────────────┼──────────────────┼─────────┼───────────────────────┤
│ k01-worker                │ k8s-kind         │ running │ 172.18.0.5            │
│                           │ kindest/node     │         │ fc00:f853:ccd:e793::5 │
├───────────────────────────┼──────────────────┼─────────┼───────────────────────┤
│ k01-worker2               │ k8s-kind         │ running │ 172.18.0.2            │
│                           │ kindest/node     │         │ fc00:f853:ccd:e793::2 │
├───────────────────────────┼──────────────────┼─────────┼───────────────────────┤
│ k01-worker3               │ k8s-kind         │ running │ 172.18.0.3            │
│                           │ kindest/node     │         │ fc00:f853:ccd:e793::3 │
╰───────────────────────────┴──────────────────┴─────────┴───────────────────────╯
```

Next, let's inspect the lab topology: First, export the kube.config file.

```
 export KUBECONFIG=/home/ubuntu/containerlab/10-calico-bgp-ippool/k01.kubeconfig
 ```
Verify the cluster nodes.
##### command
```
kubectl get nodes
```
##### output
```
kubectl get nodes
NAME                STATUS   ROLES           AGE   VERSION
k01-control-plane   Ready    control-plane   12m   v1.32.2
k01-worker          Ready    <none>          12m   v1.32.2
k01-worker2         Ready    <none>          12m   v1.32.2
k01-worker3         Ready    <none>          12m   v1.32.2
```

> [!Note]
> We are utilizing the same lab topology as the previous BGP lab that can be found here **[Lab setup](../8-calico-bgp-lb/README.md)**


### 2. Inspect IP Pools


#### 2.1 Verify the multiple IP pools configured in the `installation` resource

The following IP pools were configured in the installation resource. The installation resource can be found in the following file. [custom-resources.yaml][customResourcesDefinition]

```yaml
  calicoNetwork:
    ipPools:
    - name: default-ipv4-ippool
      blockSize: 26
      cidr: 192.168.0.0/17
      encapsulation: None
      natOutgoing: Disabled
      nodeSelector: all()
      disableBGPExport: false
    nodeAddressAutodetectionV4:
      cidrs:
        - 10.10.0.0/16
```

##### Explanation

- **name**: Identifier for the IP pool (`default-ipv4-ippool`)
- **blockSize**: Size of IP blocks allocated per node (26 = 64 IPs per block)
- **cidr**: IP address range for pod networking (`192.168.0.0/17`)
- **encapsulation**: Tunneling mode (`None` means no overlay, using native routing)
- **natOutgoing**: Controls NAT for traffic leaving the cluster (`Disabled` means no NAT)
- **nodeSelector**: Which nodes use this pool (`all()` applies to all nodes)
- **disableBGPExport**: Whether to advertise this pool via BGP (`false` means routes are advertised)
- **nodeAddressAutodetectionV4**: CIDR ranges used to detect node IP addresses (`10.10.0.0/16`)

Next, let's inspect IP pools.

##### command
```
kubectl get ippools
```

##### output

```
kubectl get ippools 
NAME                   CREATED AT
default-ipv4-ippool    2025-11-28T15:57:03Z
loadbalancer-ip-pool   2025-11-28T15:58:36Z
```

##### Explanation
Notice that there is a default IP pool configured by the operator based on the IPPool that was specified in the installation resource. You can ignore the load balance IP pool for this lab.


#### 2.2 Verify the IPAM block affinities

##### command
```
kubectl get blockaffinities
```

##### output
```
kubectl get blockaffinities
NAME                                CREATED AT
k01-control-plane-192-168-69-0-26   2025-11-28T15:57:49Z
k01-worker-192-168-42-192-26        2025-11-28T15:57:51Z
k01-worker2-192-168-88-192-26       2025-11-28T15:57:47Z
k01-worker3-192-168-46-128-26       2025-11-28T15:57:55Z
load-balancer-172-16-0-240-28       2025-11-28T15:58:37Z
```

### 3. Verify BGP Configuration

The topology diagram for this cluster setup is as follows:

![Topology Diagram](../../images/overlay-topology.png)


#### 3.1 Verify the `bgpconfiguration` Resource

The BGP configuration resource can be found in [calico-cni-config/bgp-configuration.yaml](./calico-cni-config/bgp-configuration.yaml).

##### command
```bash
kubectl get bgpconfiguration default -o yaml
```

##### output

```yaml
apiVersion: crd.projectcalico.org/v1
kind: BGPConfiguration
metadata:
  name: default
spec:
  logSeverityScreen: Info
  asNumber: 65010
  nodeToNodeMeshEnabled: false
  serviceLoadBalancerIPs:
  - cidr: 172.16.0.240/28
  prefixAdvertisements:
  - cidr: 192.168.0.0/17
    communities:
    - 65010:100
```

##### expalanation

This BGP configuration defines how Calico handles Border Gateway Protocol routing.

- `asNumber`: `65010` - The Autonomous System Number assigned to this Calico deployment for BGP peering
- `nodeToNodeMeshEnabled`: `false` - Disables the full mesh BGP peering between all nodes (requires explicit BGP peer configuration)
- `serviceLoadBalancerIPs`: Defines IP ranges for LoadBalancer services that should be advertised
  - `cidr: 172.16.0.240/28` - A /28 subnet providing 16 IP addresses for LoadBalancer services


The `prefixAdvertisements` section controls which network prefixes are advertised via BGP to external peers:

- `cidr`: `192.168.0.0/17` - The network prefix to be advertised (a /17 subnet containing 32,768 IP addresses from 192.168.0.0 to 192.168.127.255)
- `communities`: `65010:100` - BGP community tag attached to the advertised prefix
  - Communities are used for route filtering and policy decisions at BGP peers
  - Format is `AS:value` where AS matches the asNumber (65010)
  - Can be used by upstream routers to apply specific routing policies to these prefixes
  - Enables granular control over route propagation and traffic engineering

#### 3.2 Verify BGP Peers

The BGP peer resources are used to create BGP peerings from the Kubernetes cluster to the upstream network. Let's verify the BGP peers for this lab.

The BGP peer resources are used to create BGP peerings from the Kubernetes cluster to the upstream network. Let's verify the BGP peers for this lab.

[BGP peers for control, worker1 and worker2 which are in subnet or VLAN 10](./calico-cni-config/bgppeer.yaml)
[BGP peer for worker3 which is in VLAN 20](./calico-cni-config/bgppeer-w3.yaml)

The reason that there are two BGP peers is because the top of rack switch or the BGP peer IP is different for the two VLANs that we have in this topology.

##### command
```bash
kubectl get bgppeers
```

##### output
```
NAME              CREATED AT
bgppeer-vlan10    2025-11-28T15:58:00Z
bgppeer-vlan20    2025-11-28T15:58:00Z
```

Now let's inspect the detailed configuration for each BGP peer:

##### command
```bash
kubectl get bgppeer bgppeer-vlan10 -o yaml
```

##### output
```yaml
apiVersion: crd.projectcalico.org/v1
kind: BGPPeer
metadata:
  name: bgppeer-vlan-10
spec:
  peerIP: 10.10.10.1           # IP address of your Arista switch
  asNumber: 65010             # AS number of the Arista switch
  nodeSelector: vlan == '10'  
```

##### Explanation

- `peerIP`: `10.10.10.1` - The IP address of the BGP peer (router/switch in VLAN 10)
- `asNumber`: `65010` - The Autonomous System Number of the peer (iBGP peering since it matches local AS)
- `nodeSelector`: `vlan == '10'` - Applies this BGP peering only to nodes with the label `vlan=10` (control-plane, worker, worker2)

##### command
```bash
kubectl get bgppeer bgppeer-vlan20 -o yaml
```

##### output
```yaml
apiVersion: crd.projectcalico.org/v1
kind: BGPPeer
metadata:
  name: bgppeer-vlan20
spec:
  peerIP: 10.10.20.1
  asNumber: 65010
  nodeSelector: vlan == '20'
```

##### Explanation

- `peerIP`: `10.10.20.1` - The IP address of the BGP peer (router/switch in VLAN 20)
- `asNumber`: `65010` - The Autonomous System Number of the peer (iBGP peering)
- `nodeSelector`: `vlan == '20'` - Applies this BGP peering only to nodes with the label `vlan=20` (worker3)





#### 3.3 Verify BGP configuration in the ToR. 

The BGP configuration on the Arista cEOS router can be found in the startup configuration file: [ceos01-startup-config.cfg](./startup-config/ceos01-startup-config.cfg)

##### command
```bash
docker exec -it clab-calico-bgp-lb-ceos01 Cli
show running-config | s bgp
```

##### output
```bash
router bgp 65010
  router-id 10.10.10.1
  bgp listen range 10.10.10.0/24 peer-group CALICO-K8S remote-as 65010
  bgp listen range 10.10.20.0/24 peer-group CALICO-K8S remote-as 65010
  neighbor CALICO-K8S peer group
  neighbor CALICO-K8S next-hop-self
  neighbor CALICO-K8S description "Calico Kubernetes Nodes"
  neighbor CALICO-K8S route-reflector-client
  !
  address-family ipv4
    neighbor CALICO-K8S activate
    network 10.10.10.0/24
    network 10.10.20.0/24
```

##### Explanation

This BGP router configuration on the Arista cEOS device establishes it as a BGP route reflector for the Calico cluster:

- `router bgp 65010` - Configures BGP with AS number 65010 (matching the Calico ASN)
- `router-id 10.10.10.1` - Sets the BGP router ID
- `bgp listen range` - Dynamically accepts BGP connections from:
  - `10.10.10.0/24` - Control plane subnet
  - `10.10.20.0/24` - Worker nodes subnet
- `neighbor CALICO-K8S peer group` - Defines a peer group for Calico nodes
- `next-hop-self` - Router advertises itself as next-hop for reflected routes
- `route-reflector-client` - Marks peers as route reflector clients (avoids full mesh requirement)
- `address-family ipv4` - Activates IPv4 BGP for the peer group and advertises node subnets


#### 3.4 Verfiy BGP Status in the ToR


##### command

```bash
show ip bgp summary 
```

##### output

```bash
ceos#show ip bgp summary 
BGP summary information for VRF default
Router identifier 10.10.10.1, local AS number 65010
Neighbor Status Codes: m - Under maintenance
  Description              Neighbor    V AS           MsgRcvd   MsgSent  InQ OutQ  Up/Down State   PfxRcd PfxAcc
  "Calico Kubernetes Nodes 10.10.10.10 4 65010             15        14    0    0 00:05:20 Estab   2      2
  "Calico Kubernetes Nodes 10.10.10.11 4 65010             16        13    0    0 00:05:20 Estab   2      2
  "Calico Kubernetes Nodes 10.10.10.12 4 65010             16        13    0    0 00:05:20 Estab   2      2
  "Calico Kubernetes Nodes 10.10.20.20 4 65010             15        13    0    0 00:05:20 Estab   2      2
```

##### Explanation

The BGP summary shows four established peering sessions with Calico nodes:

- **10.10.10.10** - k01-control-plane (VLAN 10)
- **10.10.10.11** - k01-worker (VLAN 10)
- **10.10.10.12** - k01-worker2 (VLAN 10)
- **10.10.20.20** - k01-worker3 (VLAN 20)

Each peer has received 2 prefixes (PfxRcd) from the route reflector clients.

```mermaid
graph TB
  RR[Route Reflector<br/>cEOS ToR]
  
  CP[k01-control-plane<br/>10.10.10.10<br/>RR Client]
  W1[k01-worker<br/>10.10.10.11<br/>RR Client]
  W2[k01-worker2<br/>10.10.10.12<br/>RR Client]
  W3[k01-worker3<br/>10.10.20.20<br/>RR Client]
  
  RR <-.->|iBGP<br/>VLAN 10| CP
  RR <-.->|iBGP<br/>VLAN 10| W1
  RR <-.->|iBGP<br/>VLAN 10| W2
  RR <-.->|iBGP<br/>VLAN 20| W3
    
  style RR fill:#f96,stroke:#333,stroke-width:3px,rx:10,ry:10
  style CP fill:#9cf,stroke:#333,stroke-width:2px,rx:10,ry:10
  style W1 fill:#9cf,stroke:#333,stroke-width:2px,rx:10,ry:10
  style W2 fill:#9cf,stroke:#333,stroke-width:2px,rx:10,ry:10
  style W3 fill:#9cf,stroke:#333,stroke-width:2px,rx:10,ry:10
```





From the cEOS CLI, you can verify the BGP configuration and peering status.






docker exec -it clab-calico-bgp-lb-ceos01 Cli

docker exec -it k01-control-plane  /bin/bash
docker exec -it k01-worker3  /bin/bash


kubectl apply -f -<<EOF
apiVersion: projectcalico.org/v3
kind: CalicoNodeStatus
metadata:
  name: k01-control-plane
spec:
  classes:
    - Agent
    - BGP
    - Routes
  node: k01-control-plane
  updatePeriodSeconds: 10
EOF


kubectl apply -f -<<EOF
apiVersion: projectcalico.org/v3
kind: CalicoNodeStatus
metadata:
  name: k01-control-plane
spec:
  classes:
    - Agent
    - BGP
    - Routes
  node: k01-control-plane
  updatePeriodSeconds: 10
EOF


 kubectl get caliconodestatus k01-control-plane -o yaml

[customResourcesDefinition]: ./calico-cni-config/custom-resources.yaml