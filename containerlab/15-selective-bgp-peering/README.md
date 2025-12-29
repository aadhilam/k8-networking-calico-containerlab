# Selective BGP Peering with Node Labels

This lab demonstrates how to selectively peer Kubernetes nodes with upstream network infrastructure using Calico's BGP functionality and Kubernetes node labels. This approach is essential for large clusters where peering all nodes with ToR switches would create excessive BGP sessions.

## Why Selective BGP Peering?

In large Kubernetes clusters, establishing BGP peering from every node to the Top-of-Rack (ToR) switch creates several challenges:

| Challenge | Impact |
|-----------|--------|
| **BGP Session Overhead** | Each node requires a dedicated BGP session, consuming ToR resources |
| **Control Plane Load** | More BGP peers = more route updates = higher CPU/memory usage on network devices |
| **Scalability Limits** | ToR switches have finite BGP peer capacity (often 64-128 peers) |
| **Operational Complexity** | More sessions to monitor, troubleshoot, and maintain |

**Solution**: Designate a subset of nodes as "BGP speakers" that peer with the network infrastructure and advertise routes on behalf of the cluster.

## Lab Topology

![Selective BGP Peering Topology](../../images/selective-bgp.png)

### Traffic Flow Explanation

1. **External client** sends traffic to LoadBalancer IP `172.16.0.241`
2. **ToR switch** routes traffic to one of the BGP speaker nodes (worker or worker2) via ECMP
3. **BGP speaker node** receives the packet and uses kube-proxy/iptables to forward to the backing pod
4. **Pod** (which may be on any node, including non-BGP nodes like worker4) receives and processes the request

**Key Insight**: Even though worker3 and worker4 don't have BGP sessions with the ToR, pods running on these nodes are still reachable because traffic enters through the BGP speaker nodes and is forwarded via the internal pod network.

## Lab Setup

To setup the lab for this module **[Lab setup](../README.md#lab-setup)**

The lab folder is - `/containerlab/15-selective-bgp-peering`

## Lab

> [!Note]
> <mark>The outputs in this section will be different in your lab. When running the commands given in this section, make sure you replace IP addresses, interface names, and node names as per your lab.</mark>

### 1. Inspect ContainerLab Topology

First, let's inspect the lab topology.

##### command
```bash
containerlab inspect topology.clab.yaml 
```

Next, let's inspect the Kubernetes cluster.
```
export KUBECONFIG=/home/ubuntu/containerlab/15-selective-bgp-peering/k01.kubeconfig
```
```
kubectl get nodes
```

##### output
```
NAME                STATUS   ROLES           AGE   VERSION
k01-control-plane   Ready    control-plane   10m   v1.32.2
k01-worker          Ready    <none>          9m    v1.32.2
k01-worker2         Ready    <none>          9m    v1.32.2
k01-worker3         Ready    <none>          9m    v1.32.2
k01-worker4         Ready    <none>          9m    v1.32.2
```

The objective of this lab is to configure selective BGP peering where only designated nodes (worker and worker2) advertise load balancer IPs to the upstream router.

### 2. Verify Node Labels

In this lab, we've pre-configured two worker nodes with the label `bgp-peer=true` to designate them as BGP speakers.

##### command
```
kubectl get nodes --show-labels | grep bgp-peer
```

##### output
```
k01-worker    Ready    <none>   9m   v1.32.2   bgp-peer=true,...
k01-worker2   Ready    <none>   9m   v1.32.2   bgp-peer=true,...
```

You can also filter nodes by this label:

##### command
```
kubectl get nodes -l bgp-peer=true
```

##### output
```
NAME          STATUS   ROLES    AGE   VERSION
k01-worker    Ready    <none>   10m   v1.32.2
k01-worker2   Ready    <none>   10m   v1.32.2
```

### 3. Review BGPPeer Configuration

The key to selective peering is the `nodeSelector` field in the BGPPeer resource. Let's examine the configuration:

##### command
```
kubectl get bgppeer bgppeer-arista -o yaml
```

##### output
```yaml
apiVersion: projectcalico.org/v3
kind: BGPPeer
metadata:
  name: bgppeer-arista
spec:
  peerIP: 10.10.10.1
  asNumber: 65001
  nodeSelector: bgp-peer == "true"
```

##### Explanation

- **`nodeSelector: bgp-peer == "true"`**: This selector ensures that only nodes with the label `bgp-peer=true` will establish BGP peering with the ToR switch
- **`peerIP: 10.10.10.1`**: The IP address of the upstream Arista switch
- **`asNumber: 65001`**: The AS number of the upstream switch

Without this selector, all nodes would attempt to peer with the ToR, which is what we want to avoid in large clusters.

### 4. Configure Load Balancer IP Pool and Service

#### 4.1 Apply the Load Balancer IP Pool

```
kubectl apply -f ./k8s-manifests/lb-ippool.yaml
```

Verify the IP pool was created:

##### command
```
kubectl get ippools
```

##### output
```
NAME                   CREATED AT
default-ipv4-ippool    2025-01-01T10:00:00Z
loadbalancer-ip-pool   2025-01-01T10:05:00Z
```

#### 4.2 Create LoadBalancer Service

```
kubectl apply -f ./k8s-manifests/lb-nginx-service.yaml 
```

Verify the service:

##### command
```
kubectl get services -n default
```

##### output
```
NAME               TYPE           CLUSTER-IP     EXTERNAL-IP    PORT(S)        AGE
kubernetes         ClusterIP      10.96.0.1      <none>         443/TCP        15m
lb-nginx-service   LoadBalancer   10.96.87.127   172.16.0.241   80:30881/TCP   30s
nginx-service      ClusterIP      10.96.98.120   <none>         80/TCP         12m
```

#### 4.3 Update BGP Configuration to Advertise LB IPs

```
kubectl apply -f ./calico-cni-config/bgpconfiguration-lb.yaml 
```

### 5. Verify Selective BGP Peering

#### 5.1 Check BGP Sessions on cEOS

Exec into the cEOS container:

```
docker exec -it clab-selective-bgp-peering-ceos01 Cli
```

##### command
```
enable
show ip bgp summary
```

##### output
```
ceos#show ip bgp summary
BGP summary information for VRF default
Router identifier 10.10.10.1, local AS number 65001
Neighbor Status Codes: m - Under maintenance
  Description              Neighbor    V AS           MsgRcvd   MsgSent  InQ OutQ  Up/Down State   PfxRcd PfxAcc
  "Calico BGP Peer Node 1" 10.10.10.11 4 65010             25        22    0    0 00:10:30 Estab   1      1
  "Calico BGP Peer Node 2" 10.10.10.12 4 65010             25        22    0    0 00:10:30 Estab   1      1
```

##### Explanation

Notice that only **two BGP sessions** are established (with worker and worker2), not five. This is the benefit of selective peering:

- **worker (10.10.10.11)**: BGP session established ✓
- **worker2 (10.10.10.12)**: BGP session established ✓
- **control-plane, worker3, worker4**: No BGP sessions (as intended)

#### 5.2 Verify Routing Table

##### command
```
show ip route
```

##### output
```
VRF: default

Gateway of last resort is not set

 C        10.10.10.0/24
           directly connected, Vlan10
 B E      172.16.0.240/28 [200/0]
           via 10.10.10.11, Vlan10
 C        172.20.20.0/24
           directly connected, Management0
```

##### Explanation

The load balancer CIDR `172.16.0.240/28` is being advertised via BGP. Note that only one next hop is shown because ECMP is not yet configured. The route is learned from one of the two BGP peer nodes.

#### 5.3 Configure ECMP

Enable equal-cost multipath routing to use both BGP speakers for load distribution:

```
config t
router bgp 65001
  maximum-paths 4
end
```

Now verify the routing table again:

##### command
```
show ip route
```

##### output
```
VRF: default

Gateway of last resort is not set

 C        10.10.10.0/24
           directly connected, Vlan10
 B E      172.16.0.240/28 [200/0]
           via 10.10.10.11, Vlan10
           via 10.10.10.12, Vlan10
 C        172.20.20.0/24
           directly connected, Management0
```

##### Explanation

After enabling ECMP with `maximum-paths 4`, the routing table now shows **both BGP speaker nodes** as next hops for the load balancer CIDR. Traffic will be distributed across both paths, providing redundancy and load balancing.

### 6. Verify Connectivity

> [!Important]
> The LoadBalancer IP assigned in your lab may be different. Always retrieve the actual IP before testing connectivity.

First, retrieve the LoadBalancer service IP:

##### command
```bash
kubectl get svc lb-nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

##### output
```
172.16.0.241
```

Now test connectivity from cEOS to the nginx service using the retrieved IP:

##### command
```
telnet <LB_IP> 80
```

For example, if your LB IP is `172.16.0.241`:
```
telnet 172.16.0.241 80
```

##### output
```
Trying 172.16.0.241...
Connected to 172.16.0.241.
Escape character is 'off'.
get
HTTP/1.1 400 Bad Request
Server: nginx/1.28.0
...
Connection closed by foreign host.
```

This confirms end-to-end connectivity through the selectively peered BGP nodes.

### 7. Scaling Considerations

To add more BGP peer nodes, simply label additional nodes:

```bash
# Add a node to the BGP peer group
kubectl label node k01-worker3 bgp-peer=true

# Remove a node from the BGP peer group  
kubectl label node k01-worker3 bgp-peer-
```

Calico will automatically establish or tear down BGP sessions based on label changes.

## Summary

This lab demonstrated selective BGP peering using Calico's `nodeSelector` feature. Instead of all five nodes peering with the ToR switch, only two designated nodes (labeled `bgp-peer=true`) establish BGP sessions.

**Key Accomplishments:**
- **Node Labels**: Used Kubernetes labels (`bgp-peer=true`) to identify BGP speaker nodes
- **Selective BGPPeer**: Configured Calico BGPPeer with `nodeSelector` to target only labeled nodes
- **Reduced BGP Sessions**: Only 2 BGP sessions instead of 5 (60% reduction in this example)
- **LoadBalancer Advertisement**: Successfully advertised service IPs through selective peers

**Benefits of This Approach:**

| Benefit | Description |
|---------|-------------|
| **Scalability** | Cluster can grow without proportionally increasing BGP sessions |
| **Resource Efficiency** | ToR switches handle fewer BGP peers and route updates |
| **Flexibility** | BGP speakers can be added/removed via label changes |
| **Predictability** | Network team knows exactly which nodes participate in BGP |
| **High Availability** | Multiple BGP speakers provide redundancy |

**Production Recommendations:**
- Use 2-4 BGP speaker nodes per rack for redundancy
- Place BGP speakers strategically across failure domains
- Monitor BGP speaker health and automate failover if needed
- Consider using node affinity to ensure pods can reach BGP speakers

## Lab Cleanup

To cleanup the lab follow steps in **[Lab cleanup](../README.md#lab-cleanup)**

