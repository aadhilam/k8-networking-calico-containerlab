# Calico Network QoS - Bandwidth Limiting

This lab demonstrates Calico's Quality of Service (QoS) controls for bandwidth limiting using iperf3. You'll see how Calico can enforce bandwidth limits on pods using simple annotations.

## Why QoS Bandwidth Limiting?

In multi-tenant Kubernetes environments, a single pod can consume excessive network bandwidth and starve other workloads. QoS bandwidth limiting helps:

- **Resource Fairness**: Prevent "noisy neighbor" problems where one pod monopolizes bandwidth
- **Cost Control**: Limit bandwidth for workloads that shouldn't consume expensive network resources
- **Performance Isolation**: Ensure critical services get their required bandwidth
- **SLA Enforcement**: Enforce bandwidth limits per tenant or application tier

## How Calico QoS Works

Calico uses pod annotations to apply bandwidth limits:

| Annotation | Description |
|------------|-------------|
| `qos.projectcalico.org/ingressBandwidth` | Limits incoming traffic to the pod |
| `qos.projectcalico.org/egressBandwidth` | Limits outgoing traffic from the pod |

Values can use suffixes: `k` (kilobits), `M` (megabits), `G` (gigabits)

**Example:**
```yaml
metadata:
  annotations:
    qos.projectcalico.org/ingressBandwidth: "10M"
    qos.projectcalico.org/egressBandwidth: "10M"
```

Under the hood, Calico uses Linux Traffic Control (tc) with Token Bucket Filter (TBF) queuing discipline to enforce these limits on the pod's virtual ethernet interface.

![Network QoS](../../images/QoS.png)

## Lab Setup

To setup the lab for this module **[Lab setup](../README.md#lab-setup)**
The lab folder is - `/containerlab/12-calico-qos`

## Deployment

The `deploy.sh` script automates the complete lab setup:

1. **ContainerLab Topology Deployment**: Creates a 2-node Kind cluster
2. **Kubeconfig Setup**: Exports the Kind cluster's kubeconfig
3. **Calico Installation**: Deploys Calico CNI components
4. **Test Pod Deployment**: Deploys iperf3 server and client pods without QoS

Deploy the lab:
```bash
cd containerlab/12-calico-qos
chmod +x deploy.sh
./deploy.sh
```

## Lab Exercises

> [!Note]
> <mark>The outputs in this section will be different in your lab. When running the commands given in this section, make sure you replace IP addresses, interface names, and node names as per your lab.<mark>

### 1. Verify the Lab Setup

```bash
# Set kubeconfig
export KUBECONFIG=$(pwd)/calico-qos.kubeconfig

# Check nodes
kubectl get nodes -o wide

# Check pods
kubectl get pods -o wide
```

##### Expected output
```
NAME           READY   STATUS    RESTARTS   AGE   IP               NODE                NOMINATED NODE   READINESS GATES
iperf-client   1/1     Running   0          30s   192.168.146.66   calico-qos-worker   <none>           <none>
iperf-server   1/1     Running   0          35s   192.168.146.65   calico-qos-worker   <none>           <none>
```

### 2. Baseline Test (No QoS Limits)

First, run an iperf3 bandwidth test without any QoS limits to establish a baseline.

##### command
```bash
kubectl exec -it iperf-client -- iperf3 -c iperf-server -t 5
```

##### Expected output (approximate)
```
Connecting to host iperf-server, port 5201
[  5] local 192.168.146.66 port 45678 connected to 192.168.146.65 port 5201
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-5.00   sec  5.50 GBytes  9.44 Gbits/sec    0             sender
[  5]   0.00-5.00   sec  5.50 GBytes  9.44 Gbits/sec                  receiver

iperf Done.
```

**Key Observation:** Without QoS limits, the bandwidth is very high (typically several Gbps in a containerized environment) because there are no restrictions.

### 3. Deploy QoS-Limited Pods

Now deploy new iperf pods with Calico QoS annotations that limit bandwidth to **10 Mbps**.

##### command
```bash
kubectl apply -f tools/03-iperf-server-qos.yaml
kubectl apply -f tools/04-iperf-client-qos.yaml
```

Wait for the pods to be ready:
```bash
kubectl wait --for=condition=ready pod/iperf-server-qos --timeout=60s
kubectl wait --for=condition=ready pod/iperf-client-qos --timeout=60s
```

### 4. Verify QoS Annotations

Check that the QoS annotations are applied:

##### command
```bash
kubectl get pod iperf-server-qos -o jsonpath='{.metadata.annotations}' | jq .
```

##### Expected output
```json
{
  "qos.projectcalico.org/egressBandwidth": "10M",
  "qos.projectcalico.org/ingressBandwidth": "10M"
}
```

### 5. Test with QoS Limits Applied

Run the iperf3 test using the QoS-limited client:

##### command
```bash
kubectl exec -it iperf-client-qos -- iperf3 -c iperf-server-qos -t 5
```

##### Expected output (approximate)
```
Connecting to host iperf-server-qos, port 5201
[  5] local 192.168.183.69 port 58048 connected to 10.96.25.245 port 5201
[ ID] Interval           Transfer     Bitrate         Retr  Cwnd
[  5]   0.00-1.00   sec  35.6 MBytes   299 Mbits/sec   46    754 KBytes       
[  5]   1.00-2.00   sec  1.25 MBytes  10.5 Mbits/sec    0    754 KBytes       
[  5]   2.00-3.00   sec  1.25 MBytes  10.5 Mbits/sec    0    754 KBytes       
[  5]   3.00-4.00   sec  1.25 MBytes  10.5 Mbits/sec    0    754 KBytes       
[  5]   4.00-5.00   sec  1.25 MBytes  10.5 Mbits/sec    0    754 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-5.00   sec  39.4 MBytes  66.0 Mbits/sec   46             sender
[  5]   0.00-5.00   sec  36.7 MBytes  60.4 Mbits/sec                  receiver

iperf Done.
```

### Understanding the Output (Important!)

You may notice that the **first second shows high bandwidth (~299 Mbps)** before settling to ~10 Mbps. This is **expected behavior** due to how Token Bucket Filter (TBF) works:

| Interval | Bitrate | Retransmissions | Explanation |
|----------|---------|-----------------|-------------|
| 0-1 sec | ~299 Mbps | 46 | **Initial burst** - TBF allows burst before limiting |
| 1-2 sec | ~10.5 Mbps | 0 | QoS limit enforced ✅ |
| 2-3 sec | ~10.5 Mbps | 0 | QoS limit enforced ✅ |
| 3-4 sec | ~10.5 Mbps | 0 | QoS limit enforced ✅ |
| 4-5 sec | ~10.5 Mbps | 0 | QoS limit enforced ✅ |

**Why the initial burst?**

The TBF qdisc has a "burst" parameter (`burst 10Mb`) that allows short-term spikes at full speed until the token bucket empties. This is by design - it helps bursty traffic like web requests perform better while still enforcing long-term limits.

- The **46 retransmissions** in the first second show TCP was sending faster than allowed, causing packet drops
- After the burst, TCP's congestion control adapts and the bandwidth settles to **~10 Mbps**
- The **average (66 Mbps)** is skewed by the first-second burst - the actual sustained rate is ~10 Mbps

**Key Observation:** After the initial burst settles (~1 second), the bandwidth is limited to approximately **10 Mbps** as specified in the QoS annotations!

> **Tip:** For cleaner results, run a longer test: `iperf3 -c iperf-server-qos -t 30`. The burst becomes a smaller percentage of total time, showing an average closer to 10 Mbps.

### 6. Compare Results

| Test | Sustained Bandwidth | Notes |
|------|---------------------|-------|
| Without QoS | ~9+ Gbps | No restrictions, maximum available |
| With QoS (10M) | ~10 Mbps | Limited by Calico QoS annotations (after initial burst) |

The sustained bandwidth reduction is **~1000x** when QoS is applied!

```
Bandwidth
    ^
300 |  ████                        Without QoS: Constant high bandwidth
    |  ████   
 50 |  
 10 |       ████ ████ ████ ████   With QoS: Limited after burst
  0 |______________________________> Time
       0s   1s   2s   3s   4s   5s
        ↑
      Burst
```

### 7. Remove QoS Limits

Now let's remove the QoS annotations and verify that bandwidth returns to unrestricted levels.

> **Note:** QoS annotations are applied when the pod starts. To remove QoS limits, we need to delete and recreate the pods without the annotations.

##### command
```bash
# Delete the QoS-limited pods
kubectl delete pod iperf-server-qos iperf-client-qos
kubectl delete service iperf-server-qos
```

##### Expected output
```
pod "iperf-server-qos" deleted
pod "iperf-client-qos" deleted
service "iperf-server-qos" deleted
```

Now test again using the original pods (without QoS annotations):

##### command
```bash
kubectl exec -it iperf-client -- iperf3 -c iperf-server -t 5
```

##### Expected output (approximate)
```
Connecting to host iperf-server, port 5201
[  5] local 192.168.146.66 port 45678 connected to 192.168.146.65 port 5201
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-5.00   sec  5.50 GBytes  9.44 Gbits/sec    0             sender
[  5]   0.00-5.00   sec  5.50 GBytes  9.44 Gbits/sec                  receiver

iperf Done.
```

**Key Observation:** Without QoS annotations, the bandwidth is back to unrestricted levels (~Gbps)!

This confirms that:
- QoS limits are **only applied when annotations are present**
- Removing QoS is as simple as **deleting pods and recreating without annotations**
- The original pods (iperf-server, iperf-client) never had QoS limits

## Summary

This lab demonstrated Calico's QoS bandwidth limiting:

| Aspect | Without QoS | With QoS |
|--------|-------------|----------|
| Configuration | None | Simple pod annotations |
| Bandwidth | Unrestricted (~Gbps) | Limited (~10 Mbps) |
| Implementation | N/A | Linux tc with TBF |
| Use Case | Default pods | Multi-tenant, cost control |

**Key Takeaways:**

1. **Simple Configuration**: Just add annotations to pod metadata
2. **Immediate Effect**: QoS is applied when the pod starts
3. **Per-Pod Granularity**: Each pod can have different limits
4. **Linux tc Based**: Uses proven kernel traffic shaping

## Additional QoS Controls

Calico supports other QoS controls beyond bandwidth:

| Annotation | Description |
|------------|-------------|
| `qos.projectcalico.org/ingressPackets` | Limit incoming packets per second |
| `qos.projectcalico.org/egressPackets` | Limit outgoing packets per second |
| `qos.projectcalico.org/dscp` | Set DSCP value for traffic prioritization |

## Lab Cleanup

To cleanup the lab follow steps in **[Lab cleanup](../README.md#lab-cleanup)**

Or run:
```bash
chmod +x destroy.sh
./destroy.sh
```
