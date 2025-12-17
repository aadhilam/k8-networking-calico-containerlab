# Calico IPv6 Pod Networking

This lab demonstrates how Calico enables IPv6 addresses for pods, even when the underlying node infrastructure uses only IPv4.

## What You'll Learn

- How pods can receive IPv6 addresses in a dual-stack Kubernetes cluster
- How Calico uses VXLAN encapsulation to transport IPv6 traffic over IPv4 infrastructure
- How to create dual-stack and IPv6-only Kubernetes services

## How It Works

Pods receive both IPv4 and IPv6 addresses from Calico's IP pools. When pods on different nodes communicate over IPv6, Calico encapsulates the IPv6 packets inside IPv4 VXLAN tunnels:

```
┌─────────────────────────┐                    ┌─────────────────────────┐
│  Node 1 (IPv4 only)     │   IPv4 VXLAN       │  Node 2 (IPv4 only)     │
│  172.18.0.2             │◄──────────────────►│  172.18.0.3             │
│                         │                    │                         │
│  ┌───────────────────┐  │                    │  ┌───────────────────┐  │
│  │ Pod A             │  │   IPv6 traffic     │  │ Pod B             │  │
│  │ 192.168.1.5       │◄─┼────────────────────┼─►│ 192.168.2.10      │  │
│  │ fd00:10:244::1:5  │  │  (encapsulated)    │  │ fd00:10:244::2:a  │  │
│  └───────────────────┘  │                    │  └───────────────────┘  │
└─────────────────────────┘                    └─────────────────────────┘
```

This means you can deploy IPv6 workloads without requiring IPv6 infrastructure on your hosts.

## Lab Setup

To setup the lab for this module **[Lab setup](../README.md#lab-setup)**
The lab folder is - `/containerlab/14-calico-ipv6`

## Deployment

```bash
cd containerlab/14-calico-ipv6
chmod +x deploy.sh
./deploy.sh
```

The script deploys:
- A 3-node Kind cluster with dual-stack networking enabled
- Calico CNI with both IPv4 and IPv6 IP pools
- Test pods (DaemonSet) on each node
- Dual-stack and IPv6-only services

## Verification

> [!Note]
> <mark>The outputs in this section will be different in your lab. When running the commands given in this section, make sure you replace IP addresses, interface names, and node names as per your lab.<mark>

### 1. Set the kubeconfig

```bash
export KUBECONFIG=$(pwd)/ipv6-lab.kubeconfig
```

### 2. Check the Nodes

```bash
kubectl get nodes -o wide
```

**Output:**
```
NAME                      STATUS   ROLES           AGE   VERSION   INTERNAL-IP
ipv6-lab-control-plane    Ready    control-plane   5m    v1.28.0   172.18.0.2
ipv6-lab-worker           Ready    <none>          5m    v1.28.0   172.18.0.3
ipv6-lab-worker2          Ready    <none>          5m    v1.28.0   172.18.0.4
```

Note: Nodes have only IPv4 addresses.

### 3. Check the IP Pools

```bash
calicoctl get ippools -o wide
```

**Output:**
```
NAME                  CIDR               NAT    IPIPMODE   VXLANMODE        DISABLED   
default-ipv4-ippool   192.168.0.0/16     true   Never      CrossSubnet      false      
default-ipv6-ippool   fd00:10:244::/48   true   Never      Always           false      
```

**Explanation:**
- **default-ipv4-ippool**: IPv4 addresses for pods (192.168.x.x)
- **default-ipv6-ippool**: IPv6 addresses for pods (fd00:10:244::x)
- **VXLANMODE: Always**: IPv6 traffic is encapsulated in VXLAN

### 4. Check the Pods

```bash
kubectl get pods -o wide
```

**Output:**
```
NAME              READY   STATUS    RESTARTS   AGE   IP                NODE                     NOMINATED NODE   READINESS GATES
multitool-b95zg   1/1     Running   0          17m   192.168.195.201   ipv6-lab-control-plane   <none>           <none>
multitool-bbn2j   1/1     Running   0          17m   192.168.129.195   ipv6-lab-worker2         <none>           <none>
multitool-tddl2   1/1     Running   0          17m   192.168.106.131   ipv6-lab-worker          <none>           <none>
```

> **Note:** The `kubectl get pods -o wide` command only shows the primary (IPv4) IP address. To see both IPv4 and IPv6 addresses, use Calico's workload endpoints:

```bash
calicoctl get workloadendpoints -o wide
```

**Output:**
```
NAME                                                  WORKLOAD          NODE                     NETWORKS                                                      INTERFACE
ipv6--lab--worker2-k8s-multitool--csttt-eth0          multitool-csttt   ipv6-lab-worker2         192.168.129.194/32,fd00:10:244:4c62:c4fa:dbc4:afce:81c2/128   calib29a14d77bf
ipv6--lab--worker-k8s-multitool--hmbcg-eth0           multitool-hmbcg   ipv6-lab-worker          192.168.106.130/32,fd00:10:244:6a81:e39d:1504:3117:bc82/128   cali75b734e8e6f
ipv6--lab--control--plane-k8s-multitool--xp9c5-eth0   multitool-xp9c5   ipv6-lab-control-plane   192.168.195.200/32,fd00:10:244:a1f9:396e:2dd6:3f70:c3c8/128   calif89e07dc53d
```

**Key observation:** Each pod has **two IP addresses** in the NETWORKS column - one IPv4 and one IPv6!

### 5. Examine Pod Network Configuration

Connect to a pod:

```bash
kubectl exec -it $(kubectl get pods -l app=multitool -o name | head -1) -- sh
```

Check the IP addresses:

```bash
ip addr show eth0
```

**Output:**
```
2: eth0@if7: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UP
    link/ether 2a:3b:4c:5d:6e:7f brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.5/32 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fd00:10:244::1:5/128 scope global
       valid_lft forever preferred_lft forever
    inet6 fe80::283b:4cff:fe5d:6e7f/64 scope link
       valid_lft forever preferred_lft forever
```

**Explanation:**
- `inet 192.168.1.5/32` - Pod's IPv4 address
- `inet6 fd00:10:244::1:5/128` - Pod's global IPv6 address (from Calico pool)
- `inet6 fe80::...` - Link-local IPv6 address (auto-generated)

### 6. Test IPv6 Connectivity

From inside a pod, ping another pod using IPv6:

```bash
# Get another pod's IPv6 address from 'kubectl get pods -o wide'
ping6 -c 3 fd00:10:244::2:a
```

**Output:**
```
PING fd00:10:244::2:a (fd00:10:244::2:a): 56 data bytes
64 bytes from fd00:10:244::2:a: seq=0 ttl=62 time=0.543 ms
64 bytes from fd00:10:244::2:a: seq=1 ttl=62 time=0.321 ms
64 bytes from fd00:10:244::2:a: seq=2 ttl=62 time=0.298 ms
```

Exit the pod:
```bash
exit
```

## IPv6 Services

### Check the Services

```bash
kubectl get svc
```

**Output:**
```
NAME                   TYPE        CLUSTER-IP                       PORT(S)
kubernetes             ClusterIP   10.96.0.1,fd00:10:96::1          443/TCP
multitool-dual-stack   ClusterIP   10.96.45.12,fd00:10:96::abcd     80/TCP
multitool-ipv6-only    ClusterIP   fd00:10:96::1234                 80/TCP
```

**Explanation:**
- **multitool-dual-stack**: Has both IPv4 and IPv6 ClusterIPs
- **multitool-ipv6-only**: Has only an IPv6 ClusterIP

### Service Configuration

The dual-stack service is configured with:
```yaml
spec:
  ipFamilyPolicy: RequireDualStack
  ipFamilies:
    - IPv4
    - IPv6
```

The IPv6-only service is configured with:
```yaml
spec:
  ipFamilyPolicy: SingleStack
  ipFamilies:
    - IPv6
```

### Test Service Connectivity

From inside a pod:

```bash
kubectl exec -it $(kubectl get pods -l app=multitool -o name | head -1) -- sh
```

```bash
# Access dual-stack service via IPv6
curl -6 http://[fd00:10:96::abcd]:80

# Access IPv6-only service
curl http://[fd00:10:96::1234]:80
```

## Key Concepts

### Application IPv6 Support


<mark>⚠️ **Important:** For IPv6 services to work, your application must listen on IPv6 addresses! Many applications default to IPv4 only (`0.0.0.0`). If your IPv6 service isn't working, check that the application is bound to `[::]` (all IPv6 addresses).</mark>

For example, nginx needs explicit configuration:

```nginx
server {
  listen 8080;        # IPv4
  listen [::]:8080;   # IPv6 - must be explicitly added!
}
```

Check if your application is listening on IPv6:
```bash
kubectl exec -it <pod> -- netstat -tlnp
# Look for :::port entries (IPv6) vs 0.0.0.0:port (IPv4 only)
```

### Why VXLAN for IPv6?

Without IPv6 infrastructure on the hosts, Calico cannot route IPv6 packets directly between nodes. VXLAN solves this by:

1. Encapsulating the IPv6 packet inside a UDP packet
2. Using IPv4 addresses for the outer packet headers
3. Decapsulating at the destination node

This adds some overhead (~50 bytes per packet) but enables IPv6 without infrastructure changes.

### IP Pool Configuration

```yaml
# IPv6 Pool from custom-resources.yaml
- name: default-ipv6-ippool
  blockSize: 122          # 64 IPs per node block
  cidr: fd00:10:244::/48  # Address range
  encapsulation: VXLAN    # Enables IPv6 over IPv4 infrastructure
  natOutgoing: Enabled    # NAT for external traffic
```

### Block Allocation

Each node receives blocks from both pools:

```bash
kubectl get blockaffinities
```

You'll see both IPv4 (/26) and IPv6 (/122) blocks assigned to each node.

## Summary

This lab demonstrates that:

1. **Pods can have IPv6 addresses** even when nodes only have IPv4
2. **VXLAN encapsulation** transports IPv6 packets over IPv4 infrastructure  
3. **Dual-stack services** can have both IPv4 and IPv6 ClusterIPs
4. **IPv6-only services** are also supported for pure IPv6 workloads

This approach is useful when you need to support IPv6 applications but don't have IPv6 infrastructure available.

## Lab Cleanup

```bash
./destroy.sh
```

Or follow steps in **[Lab cleanup](../README.md#lab-cleanup)**
