# IP Reservations and Static IPs for Pods

This lab demonstrates how to assign static IP addresses to Kubernetes pods using Calico IPAM. You'll learn how to use pod annotations to request specific IP addresses.

## Why Static IPs for Pods?

By default, Kubernetes pods receive dynamically assigned IP addresses from the CNI. However, some use cases require stable, predictable IP addresses:

- **Legacy Application Integration**: Applications that require whitelisting specific IPs
- **External DNS Records**: Creating DNS entries that point directly to pods
- **Debugging and Monitoring**: Easier identification of specific pods in logs
- **Stateful Workloads**: Applications that need consistent network identity

## How Calico Static IP Assignment Works

Calico allows you to specify a static IP for a pod using the annotation:

```yaml
metadata:
  annotations:
    cni.projectcalico.org/ipAddrs: "[\"192.168.1.100\"]"
```

**Requirements:**
- The IP address must be within a configured Calico IPPool
- The IP must not be currently in use by another pod
- The annotation must be present when the pod is created (adding it later has no effect)

## Lab Setup

To setup the lab for this module **[Lab setup](../README.md#lab-setup)**
The lab folder is - `/containerlab/16-static-ip`

## Deployment

The `deploy.sh` script automates the complete lab setup:

1. **ContainerLab Topology Deployment**: Creates a 2-node Kind cluster
2. **Kubeconfig Setup**: Exports the Kind cluster's kubeconfig
3. **Calico Installation**: Deploys Calico CNI components
4. **Test Pod Deployment**: Deploys sample pods for testing

Deploy the lab:
```bash
cd containerlab/16-static-ip
chmod +x deploy.sh
./deploy.sh
```

## Lab Exercises

> [!Note]
> <mark>The outputs in this section will be different in your lab. When running the commands given in this section, make sure you replace IP addresses, interface names, and node names as per your lab.<mark>

### 1. Verify the Lab Setup

```bash
# Set kubeconfig
export KUBECONFIG=$(pwd)/k01.kubeconfig

# Check nodes
kubectl get nodes -o wide

# Check Calico IPPool
kubectl get ippools -o custom-columns='NAME:.metadata.name,CIDR:.spec.cidr'
```

##### Expected output
```
NAME                  CIDR
default-ipv4-ippool   192.168.0.0/16
```

### 2. View the IP Reservation

The deploy script already created an IP reservation for the `192.168.100.8/29` range (8 IPs: 192.168.100.8-15). This prevents Calico from automatically assigning IPs in this range, reserving them for static assignments.

##### command
```bash
kubectl get ipreservations
kubectl get ipreservation reserved-ips -o yaml
```

##### Expected output
```yaml
apiVersion: crd.projectcalico.org/v1
kind: IPReservation
metadata:
  name: reserved-ips
spec:
  reservedCIDRs:
  - 192.168.100.8/29
```

**Key Observation:** IPs in `192.168.100.8/29` (192.168.100.8-15) are reserved and won't be automatically assigned to pods, but can still be used for static IP assignments.

### 3. Verify Dynamic Pod Has IP Outside Reserved Range

The dynamic pod was deployed during setup. Notice its IP is NOT in the reserved `192.168.100.8/29` range:

##### command
```bash
kubectl get pod dynamic-pod -o wide
```

##### Expected output
```
NAME          READY   STATUS    RESTARTS   AGE   IP              NODE         
dynamic-pod   1/1     Running   0          10s   192.168.x.x     k01-worker
```

**Key Observation:** The pod receives a randomly assigned IP from the `192.168.0.0/16` pool, but NOT from the reserved `192.168.100.8/29` range.

### 4. Deploy a Pod with Static IP

Now deploy a pod with a specific static IP address using the Calico annotation.

##### command
```bash
kubectl apply -f tools/02-static-pod.yaml
kubectl wait --for=condition=ready pod/static-pod --timeout=60s
```

Check the assigned IP:

##### command
```bash
kubectl get pod static-pod -o wide
```

##### Expected output
```
NAME         READY   STATUS    RESTARTS   AGE   IP               NODE
static-pod   1/1     Running   0          10s   192.168.100.10   k01-worker
```

**Key Observation:** The pod received exactly the IP address we specified: `192.168.100.10` (from the reserved range)

### 5. Verify the Static IP Annotation

Let's examine the pod annotation to confirm it's set correctly:

##### command
```bash
kubectl get pod static-pod -o jsonpath='{.metadata.annotations}' | jq .
```

##### Expected output
```json
{
  "cni.projectcalico.org/ipAddrs": "[\"192.168.100.10\"]"
}
```

### 6. Test Connectivity to the Static IP

Verify that the static IP is reachable from other pods:

##### command
```bash
kubectl exec -it dynamic-pod -- ping -c 3 192.168.100.10
```

##### Expected output
```
PING 192.168.100.10 (192.168.100.10): 56 data bytes
64 bytes from 192.168.100.10: seq=0 ttl=63 time=0.123 ms
64 bytes from 192.168.100.10: seq=1 ttl=63 time=0.089 ms
64 bytes from 192.168.100.10: seq=2 ttl=63 time=0.091 ms

--- 192.168.100.10 ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
```

### 7. Attempt to Use an Already Assigned IP

Let's see what happens when we try to create another pod with the same static IP:

##### command
```bash
kubectl apply -f tools/03-duplicate-ip-pod.yaml
```

Check the pod status:

##### command
```bash
kubectl get pod duplicate-pod
kubectl describe pod duplicate-pod | grep -A5 Events
```

##### Expected output
```
NAME            READY   STATUS              RESTARTS   AGE
duplicate-pod   0/1     ContainerCreating   0          30s
```

The pod will remain in `ContainerCreating` state because the IP is already in use.

##### command
```bash
kubectl describe pod duplicate-pod | tail -10
```

You'll see an error message indicating the IP address is already assigned.

Clean up the failed pod:
```bash
kubectl delete pod duplicate-pod
```

### 8. Delete and Recreate Pod with Same Static IP

Static IPs persist through pod deletion and recreation. Let's verify:

##### command
```bash
# Delete the static pod
kubectl delete pod static-pod
kubectl wait --for=delete pod/static-pod --timeout=60s

# Recreate with the same static IP
kubectl apply -f tools/02-static-pod.yaml
kubectl wait --for=condition=ready pod/static-pod --timeout=60s

# Verify the IP is the same
kubectl get pod static-pod -o wide
```

##### Expected output
```
NAME         READY   STATUS    RESTARTS   AGE   IP               NODE
static-pod   1/1     Running   0          5s    192.168.100.10   k01-worker
```

**Key Observation:** The pod receives the same static IP `192.168.100.10` after recreation.

## Summary

This lab demonstrated Calico's static IP assignment for pods:

| Aspect | Dynamic IP | Static IP |
|--------|------------|-----------|
| Configuration | None (default) | Pod annotation |
| IP Selection | Automatic from pool | User-specified |
| Persistence | Changes on pod restart | Same IP on recreation |
| Use Case | General workloads | Legacy integration |

**Key Takeaways:**

1. **Reserve First**: Use IPReservation to reserve IP ranges before assigning static IPs
2. **Simple Annotation**: Use `cni.projectcalico.org/ipAddrs` annotation to assign static IP
3. **IPPool Requirement**: Static IP must be within a configured IPPool
4. **Uniqueness**: Each static IP can only be used by one pod at a time
5. **Apply at Creation**: Annotation must be present when pod is created

## Lab Cleanup

To cleanup the lab follow steps in **[Lab cleanup](../README.md#lab-cleanup)**

Or run:
```bash
chmod +x destroy.sh
./destroy.sh
```

