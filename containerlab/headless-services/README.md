# Kubernetes Headless Services

This lab demonstrates how Kubernetes headless services work and how they differ from regular ClusterIP services. Headless services provide direct DNS-to-Pod IP resolution without a virtual IP (VIP), enabling direct pod-to-pod communication and are essential for stateful applications.

## Why are Headless Services Required

In standard Kubernetes services, a ClusterIP provides load balancing through kube-proxy and a stable VIP. However, some use cases require direct access to individual pods:

- **Stateful Applications**: Databases like Redis, MySQL, PostgreSQL, MongoDB, and Cassandra need clients to connect to specific replicas (e.g., primary vs replica).
- **Peer Discovery**: Distributed systems (Kafka, Elasticsearch, etcd) need pods to discover and communicate directly with each other.
- **Client-Side Load Balancing**: Applications that implement their own load balancing logic need access to all pod IPs.
- **Service Mesh Integration**: Some service meshes prefer direct pod addressing for fine-grained traffic control.

### How Headless Services Differ from ClusterIP

| Feature | ClusterIP Service | Headless Service |
|---------|-------------------|------------------|
| Virtual IP (VIP) | Yes (`clusterIP: <IP>`) | No (`clusterIP: None`) |
| DNS Resolution | Returns Service VIP | Returns Pod IPs directly |
| Load Balancing | kube-proxy handles | Client-side or none |
| iptables Rules | Created by kube-proxy | None (no VIP to NAT) |
| Use Case | General service discovery | Stateful apps, peer discovery |

### DNS Records Created by Headless Services

Headless services create different DNS records depending on the workload type:

**With StatefulSet:**
- **A Record**: `<service>.<namespace>.svc.cluster.local` → Returns all Pod IPs
- **A Record per Pod**: `<pod-name>.<service>.<namespace>.svc.cluster.local` → Returns specific Pod IP
- Example: `redis-0.redis-headless.default.svc.cluster.local` → Pod IP

**With Deployment/ReplicaSet:**
- **A Record**: `<service>.<namespace>.svc.cluster.local` → Returns all Pod IPs
- No individual pod DNS records (pods don't have stable identities)

## Lab Setup
To setup the lab for this module **[Lab setup](../README.md#lab-setup)**
The lab folder is - `/containerlab/headless-services`

## Deployment

1. **ContainerLab Topology Deployment**: Creates a 3-node Kind cluster using the `headless-services.clab.yaml` configuration
2. **Kubeconfig Setup**: Exports the Kind cluster's kubeconfig for kubectl access
3. **Calico Installation**: Downloads and installs calicoctl, then deploys Calico CNI components:
    - Calico Operator CRDs
    - Tigera Operator
    - Custom Calico resources with IPAM configuration
4. **Test Workload Deployment**: Deploys Redis StatefulSet and Nginx Deployment with headless services, plus multitool pods for testing
5. **Verification**: Waits for all Calico components to become available before completion

Deploy the lab using:
```bash
cd containerlab/headless-services
chmod +x deploy.sh
./deploy.sh
```

## Lab

After deployment, verify the cluster is ready by checking the ContainerLab topology status:

### 1. Inspect ContainerLab Topology

```bash
containerlab inspect -t headless-services.clab.yaml
```

##### output
```
╭─────────────────────────────────┬──────────────────────┬─────────┬───────────────────────╮
│              Name               │      Kind/Image      │  State  │     IPv4/6 Address    │
├─────────────────────────────────┼──────────────────────┼─────────┼───────────────────────┤
│ headless-services-control-plane │ k8s-kind             │ running │ 172.18.0.3            │
│                                 │ kindest/node:v1.28.0 │         │ fc00:f853:ccd:e793::3 │
├─────────────────────────────────┼──────────────────────┼─────────┼───────────────────────┤
│ headless-services-worker        │ k8s-kind             │ running │ 172.18.0.2            │
│                                 │ kindest/node:v1.28.0 │         │ fc00:f853:ccd:e793::2 │
├─────────────────────────────────┼──────────────────────┼─────────┼───────────────────────┤
│ headless-services-worker2       │ k8s-kind             │ running │ 172.18.0.4            │
│                                 │ kindest/node:v1.28.0 │         │ fc00:f853:ccd:e793::4 │
╰─────────────────────────────────┴──────────────────────┴─────────┴───────────────────────╯
```

### 2. Verify pods and services

```bash
# Set kubeconfig to use the cluster
export KUBECONFIG=/home/ubuntu/containerlab/headless-services/headless-services.kubeconfig

# Check all pods
kubectl get pods -o wide
```

##### output
```
NAME                                READY   STATUS    RESTARTS   AGE   IP               NODE                              NOMINATED NODE   READINESS GATES
multitool-2p4xk                     1/1     Running   0          5m    192.168.202.194  headless-services-worker          <none>           <none>
multitool-8h2js                     1/1     Running   0          5m    192.168.145.9    headless-services-control-plane   <none>           <none>
multitool-k9d3f                     1/1     Running   0          5m    192.168.156.3    headless-services-worker2         <none>           <none>
nginx-deployment-55d7bb4b86-vg4lt   1/1     Running   0          5m    192.168.156.5    headless-services-worker2         <none>           <none>
nginx-deployment-55d7bb4b86-xqh9d   1/1     Running   0          5m    192.168.202.196  headless-services-worker          <none>           <none>
redis-0                             1/1     Running   0          5m    192.168.202.195  headless-services-worker          <none>           <none>
redis-1                             1/1     Running   0          5m    192.168.156.4    headless-services-worker2         <none>           <none>
redis-2                             1/1     Running   0          5m    192.168.145.10   headless-services-control-plane   <none>           <none>
```

- **redis-0, redis-1, redis-2**: StatefulSet pods with predictable, ordered names
- **nginx-deployment-***: Deployment pods with random suffixes
- **multitool-***: DaemonSet pods for testing on each node

##### command
```bash
kubectl get services
```

##### output
```
NAME              TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
kubernetes        ClusterIP   10.96.0.1      <none>        443/TCP    10m
nginx-clusterip   ClusterIP   10.96.204.67   <none>        80/TCP     5m
nginx-headless    ClusterIP   None           <none>        80/TCP     5m
redis-headless    ClusterIP   None           <none>        6379/TCP   5m
```

- **nginx-clusterip**: Regular ClusterIP service with VIP `10.96.204.67`
- **nginx-headless**: Headless service (`ClusterIP: None`) for the Deployment
- **redis-headless**: Headless service (`ClusterIP: None`) for the Redis StatefulSet

### 3. Compare ClusterIP vs Headless Service DNS Resolution

Exec into a multitool pod to test DNS resolution:

```bash
kubectl exec -it $(kubectl get pods -l app=multitool -o jsonpath='{.items[0].metadata.name}') -- sh
```

#### 3.1 - Regular ClusterIP Service DNS

##### command
```bash
dig +search nginx-clusterip
```

##### output
```
;; QUESTION SECTION:
;nginx-clusterip.default.svc.cluster.local. IN A

;; ANSWER SECTION:
nginx-clusterip.default.svc.cluster.local. 30 IN A 10.96.204.67
```

- Returns the **Service VIP** (10.96.204.67)
- kube-proxy handles load balancing to backend pods
- Client sees only one IP regardless of replica count

#### 3.2 - Headless Service DNS (Deployment)

##### command
```bash
dig +search nginx-headless
```

##### output
```
;; QUESTION SECTION:
;nginx-headless.default.svc.cluster.local. IN A

;; ANSWER SECTION:
nginx-headless.default.svc.cluster.local. 30 IN A 192.168.156.5
nginx-headless.default.svc.cluster.local. 30 IN A 192.168.202.196
```

- Returns **all Pod IPs** directly (no VIP)
- Client receives multiple A records
- Client-side load balancing or selection required
- No iptables/IPVS rules created for this service

#### 3.3 - Headless Service DNS (Redis StatefulSet)

##### command
```bash
dig +search redis-headless
```

##### output
```
;; QUESTION SECTION:
;redis-headless.default.svc.cluster.local. IN A

;; ANSWER SECTION:
redis-headless.default.svc.cluster.local. 30 IN A 192.168.202.195
redis-headless.default.svc.cluster.local. 30 IN A 192.168.156.4
redis-headless.default.svc.cluster.local. 30 IN A 192.168.145.10
```

- Returns all **Redis Pod IPs**
- Each pod has a stable network identity

### 4. Redis Pod-Specific DNS Records

The key advantage of headless services with StatefulSets is individual pod DNS records. This is essential for databases where you need to connect to specific instances (e.g., primary vs replica).

#### 4.1 - Query Individual Redis Pod DNS

##### command
```bash
dig +search redis-0.redis-headless
```

##### output
```
;; QUESTION SECTION:
;redis-0.redis-headless.default.svc.cluster.local. IN A

;; ANSWER SECTION:
redis-0.redis-headless.default.svc.cluster.local. 30 IN A 192.168.202.195
```

- **redis-0.redis-headless** resolves to `redis-0`'s specific IP
- Enables direct connection to a specific Redis instance

##### command
```bash
dig +search redis-1.redis-headless
```

##### output
```
;; ANSWER SECTION:
redis-1.redis-headless.default.svc.cluster.local. 30 IN A 192.168.156.4
```

##### command
```bash
dig +search redis-2.redis-headless
```

##### output
```
;; ANSWER SECTION:
redis-2.redis-headless.default.svc.cluster.local. 30 IN A 192.168.145.10
```

#### 4.2 - Test Connectivity to Specific Redis Instance

##### command
```bash
# Connect to redis-0 using its DNS name
redis-cli -h redis-0.redis-headless ping
```

##### output
```
PONG
```

- Direct connection to `redis-0` via its DNS name
- Essential for database primary/replica selection

##### command
```bash
# Set a value on redis-0
redis-cli -h redis-0.redis-headless SET mykey "Hello from redis-0"
```

##### output
```
OK
```

##### command
```bash
# Verify it's stored on redis-0
redis-cli -h redis-0.redis-headless GET mykey
```

##### output
```
"Hello from redis-0"
```

##### command
```bash
# Note: redis-1 and redis-2 are independent instances in this lab
# In production Redis Cluster, data would be replicated
redis-cli -h redis-1.redis-headless GET mykey
```

##### output
```
(nil)
```

- Each Redis instance is independent in this lab setup
- In a real Redis Cluster or Sentinel setup, headless services enable peer discovery for replication

### 5. Verify No iptables Rules for Headless Services

Exit from the pod and connect to a worker node:

```bash
exit
docker exec -it headless-services-worker /bin/bash
```

#### 5.1 - Check iptables for ClusterIP Service

##### command
```bash
iptables -t nat -S KUBE-SERVICES | grep nginx-clusterip
```

##### output
```
-A KUBE-SERVICES -d 10.96.204.67/32 -p tcp -m comment --comment "default/nginx-clusterip:http cluster IP" -m tcp --dport 80 -j KUBE-SVC-XXXXXXXX
```

- iptables rules exist for ClusterIP service
- kube-proxy programs DNAT rules for load balancing

#### 5.2 - Check iptables for Headless Services

##### command
```bash
iptables -t nat -S KUBE-SERVICES | grep nginx-headless
```

##### output
```
(no output)
```

- **No iptables rules** for headless services
- There's no VIP to NAT traffic to
- DNS returns pod IPs directly; routing uses normal pod routing

##### command
```bash
iptables -t nat -S KUBE-SERVICES | grep redis-headless
```

##### output
```
(no output)
```

- Same for Redis headless service - no iptables rules

#### 5.3 - Verify Endpoints

```bash
exit
kubectl get endpoints
```

##### output
```
NAME              ENDPOINTS                                               AGE
kubernetes        172.18.0.3:6443                                         15m
nginx-clusterip   192.168.156.5:80,192.168.202.196:80                     10m
nginx-headless    192.168.156.5:80,192.168.202.196:80                     10m
redis-headless    192.168.145.10:6379,192.168.156.4:6379,192.168.202.195:6379   10m
```

- Both ClusterIP and Headless services have endpoints
- Endpoints list the backend pod IPs
- Headless services use endpoints for DNS resolution only (not for kube-proxy)

### 6. EndpointSlices for Headless Services

##### command
```bash
kubectl get endpointslices -o wide
```

##### output
```
NAME                    ADDRESSTYPE   PORTS   ENDPOINTS                                           AGE
kubernetes              IPv4          6443    172.18.0.3                                          15m
nginx-clusterip-xxxxx   IPv4          80      192.168.156.5,192.168.202.196                       10m
nginx-headless-xxxxx    IPv4          80      192.168.156.5,192.168.202.196                       10m
redis-headless-xxxxx    IPv4          6379    192.168.145.10,192.168.156.4,192.168.202.195        10m
```

- EndpointSlices are created for both service types
- CoreDNS uses EndpointSlices to respond to DNS queries for headless services

### 7. Practical Use Case: Database Primary Selection

In a real database cluster, clients can connect to specific roles using headless service DNS:

```bash
kubectl exec -it $(kubectl get pods -l app=multitool -o jsonpath='{.items[0].metadata.name}') -- sh
```

##### command
```bash
# Connect to what would be the "primary" (redis-0)
nslookup redis-0.redis-headless
```

##### output
```
Server:		10.96.0.10
Address:	10.96.0.10#53

Name:	redis-0.redis-headless.default.svc.cluster.local
Address: 192.168.202.195
```

##### command
```bash
# Connect to "replica" pods
nslookup redis-1.redis-headless
nslookup redis-2.redis-headless
```

##### command
```bash
# Test Redis connectivity to the primary
redis-cli -h redis-0.redis-headless INFO server | head -5
```

##### output
```
# Server
redis_version:7.2.4
redis_git_sha1:00000000
redis_git_dirty:0
redis_build_id:abc123
```

This pattern is used by:
- **Redis Sentinel**: Discovers Redis instances via `redis-0.redis-headless`, `redis-1.redis-headless`
- **Redis Cluster**: Nodes announce themselves using their headless DNS names
- **MySQL**: Connect to `mysql-0.mysql-headless` for primary, `mysql-1.mysql-headless` for replica
- **PostgreSQL**: Primary/standby selection via DNS
- **MongoDB**: ReplicaSet member discovery
- **Kafka**: Broker discovery via headless service

```bash
exit
```

## Summary

This lab demonstrated the key differences between ClusterIP and headless services:

| Aspect | ClusterIP Service | Headless Service |
|--------|-------------------|------------------|
| DNS Response | Service VIP | All Pod IPs |
| Load Balancing | kube-proxy (iptables/IPVS) | Client-side |
| iptables Rules | Yes | No |
| Pod-specific DNS | No | Yes (with StatefulSet) |
| Use Case | General services | Stateful apps, peer discovery |

Key takeaways:
- **Headless services** (`clusterIP: None`) bypass kube-proxy entirely
- DNS returns **pod IPs directly** instead of a VIP
- **StatefulSets** with headless services get individual pod DNS records (`<pod>.<service>.<ns>.svc.cluster.local`)
- **No iptables rules** are created for headless services
- Essential for **databases like Redis** requiring direct pod addressing and peer discovery

## Additional Notes

### When to Use Headless Services

1. **StatefulSets**: Always pair with headless services for stable network identities
2. **Database Clusters**: Redis, MySQL, PostgreSQL, MongoDB, Cassandra
3. **Distributed Systems**: Kafka, Elasticsearch, etcd, ZooKeeper
4. **Custom Load Balancing**: When clients implement their own balancing logic
5. **Service Mesh**: Some meshes prefer direct pod addressing

### Headless Service Gotchas

- **No load balancing by default**: DNS returns all IPs; client must handle selection
- **DNS caching**: Clients may cache DNS responses; TTL is typically 30 seconds
- **Pod churn**: As pods restart, IPs change; clients should re-resolve DNS periodically
- **Not for general services**: Use ClusterIP for stateless services that benefit from kube-proxy load balancing

### DNS Record Types

- **A Record**: Returns IPv4 addresses
- **AAAA Record**: Returns IPv6 addresses (in dual-stack clusters)
- **SRV Record**: Returns port and hostname (use `dig SRV _redis._tcp.redis-headless.default.svc.cluster.local`)

## Lab Cleanup
to cleanup the lab follow steps in **[Lab cleanup](../README.md#lab-cleanup)**
