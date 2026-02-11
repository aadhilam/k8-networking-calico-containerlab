# Calico DSCP Markings with Network QoS

This lab demonstrates how Calico can set DSCP (Differentiated Services Code Point) markings on pod egress traffic, enabling upstream network devices to classify and prioritize that traffic accordingly.

## What is DSCP?

DSCP is a 6-bit field in the IP header that allows network devices to classify and prioritize traffic. It's part of the DiffServ (Differentiated Services) architecture defined in RFC 2474.

| DSCP Class | Decimal | Binary | Typical Use |
|------------|---------|--------|-------------|
| **EF** (Expedited Forwarding) | 46 | 101110 | Voice, real-time video |
| **AF11** (Assured Forwarding) | 10 | 001010 | Low-priority bulk data |
| **AF21** | 18 | 010010 | Medium-priority traffic |
| **CS3** (Class Selector) | 24 | 011000 | Signaling traffic |
| **DF** (Default) | 0 | 000000 | Best effort (no marking) |

## Why DSCP with Calico?

Calico's DSCP annotation (`qos.projectcalico.org/dscp`) marks egress traffic at the pod level, allowing:

1. **End-to-end QoS**: Traffic is marked at the source, so all network devices along the path can honor the priority
2. **Network-level enforcement**: Switches and routers can apply bandwidth policies based on DSCP values
3. **Application-agnostic**: No application changes needed - Calico marks all egress traffic from the pod

## Lab Architecture

```
    ┌─────────────────────────────────────────────────────────────┐
    │                    Kubernetes Cluster                       │
    │                                                             │
    │  ┌──────────────┐      ┌──────────────┐                   │
    │  │ Control      │      │ Worker       │                   │
    │  │ Plane        │      │ Node         │                   │
    │  │ 10.10.10.10  │      │ 10.10.10.11 │                   │
    │  └──────┬───────┘      └──────┬───────┘                   │
    │         │                     │                            │
    │         └──────────┬──────────┘                            │
    │                    │                                       │
    │              Pods: │                                       │
    │              ├── sender-no-dscp   (DSCP 0)                │
    │              ├── sender-dscp-af11 (DSCP 10)               │
    │              └── sender-dscp-ef   (DSCP 46)               │
    └────────────────────┼───────────────────────────────────────┘
                         │
                         │ DSCP-marked traffic
                         │
         ┌───────────────▼───────────────┐
         │      Linux Router             │
         │  10.10.10.1  │  10.30.30.1   │
         │              │                │
         │  ┌───────────┴───────────┐   │
         │  │   Linux tc QoS         │   │
         │  │  ┌──────┐  ┌──────┐   │   │
         │  │  │AF11  │  │ EF   │   │   │
         │  │  │1 Mbps│  │5 Mbps│   │   │
         │  │  └──────┘  └──────┘   │   │
         │  └───────────────────────┘   │
         └───────────────┬───────────────┘
                         │
                         │ Throttled traffic
                         │
         ┌───────────────▼───────────────┐
         │      Client                   │
         │  10.30.30.100                 │
         │  (iperf3 server)              │
         └───────────────────────────────┘
    
    Traffic Flow:
    Pod → Worker Node → Router (eth1) → Router (eth2, tc QoS) → Client
    
    DSCP Throttling:
    ├── sender-no-dscp   (DSCP 0)  → Unlimited bandwidth
    ├── sender-dscp-af11 (DSCP 10) → Throttled to 1 Mbps
    └── sender-dscp-ef   (DSCP 46) → Throttled to 5 Mbps
```

## Lab Setup

To setup the lab for this module **[Lab setup](../readme.md#lab-setup)**

The lab folder is - `/containerlab/23-calico-dscp`

## Deployment

```bash
cd containerlab/23-calico-dscp
chmod +x deploy.sh
./deploy.sh
```

## Lab Exercises

> [!Note]
> <mark>The outputs in this section will be different in your lab. Replace IP addresses and values as per your lab.</mark>

### 1. Set Up Environment

```bash
export KUBECONFIG=$(pwd)/k01.kubeconfig
kubectl get pods -o wide
```

Expected output:
```
NAME               READY   STATUS    RESTARTS   AGE   IP              NODE
sender-no-dscp     1/1     Running   0          1m    192.168.x.x     k01-worker
sender-dscp-af11   1/1     Running   0          1m    192.168.x.x     k01-worker
sender-dscp-ef     1/1     Running   0          1m    192.168.x.x     k01-worker
```

### 2. Verify DSCP Annotations

```bash
kubectl get pod sender-dscp-af11 -o jsonpath='{.metadata.annotations}'
```

```json
{"qos.projectcalico.org/dscp":"AF11"}
```

### 3. Start iperf3 Server on Client

In a **separate terminal**, start the iperf3 server on the client container:

```bash
sudo docker exec -it clab-calico-dscp-client iperf3 -s
```

Keep this running for all tests.

### 5. Test Without DSCP (Baseline)

Run iperf3 from the pod **without** DSCP marking:

```bash
kubectl exec -it sender-no-dscp -- iperf3 -c 10.30.30.100 -t 10
```

Expected result: **High bandwidth** (no throttling)
```
[ ID] Interval           Transfer     Bitrate
[  5]   0.00-10.00  sec  1.10 GBytes   944 Mbits/sec    sender
```

### 6. Test with DSCP AF11 (1 Mbps Throttle)

Run iperf3 from the pod with **DSCP AF11** marking:

```bash
kubectl exec -it sender-dscp-af11 -- iperf3 -c 10.30.30.100 -t 10
```

Expected result: **~1 Mbps** (throttled by switch)
```
[ ID] Interval           Transfer     Bitrate
[  5]   0.00-10.00  sec  1.19 MBytes  1.00 Mbits/sec    sender
```

### 7. Test with DSCP EF (5 Mbps Throttle)

Run iperf3 from the pod with **DSCP EF** marking:

```bash
kubectl exec -it sender-dscp-ef -- iperf3 -c 10.30.30.100 -t 10
```

Expected result: **~5 Mbps** (throttled by Linux router)
```
[ ID] Interval           Transfer     Bitrate
[  5]   0.00-10.00  sec  5.96 MBytes  5.00 Mbits/sec    sender
```

### 8. Verify DSCP Marking with Packet Capture

You can capture packets at multiple points to verify DSCP markings are being applied:

#### Quick Method: Use the Helper Script

```bash
cd containerlab/23-calico-dscp
./capture-dscp.sh
```

This interactive script lets you choose where to capture and can compare all pods automatically.

#### Option A: Capture on the Router (Recommended)

The router is the best place to see DSCP markings as traffic passes through:

```bash
# Terminal 1: Start packet capture on router
sudo docker exec -it clab-calico-dscp-router tcpdump -i eth3 -v -n 'ip' -c 20

# Terminal 2: Generate traffic from DSCP-marked pod
kubectl exec -it sender-dscp-af11 -- ping -c 5 10.30.30.100
```

Look for the **tos** field in tcpdump output:
```
IP (tos 0x28, ttl 64, id 12345, ...) 10.30.30.1 > 10.30.30.100: ICMP echo request
```

**DSCP Value Reference:**
- `tos 0x00` = DSCP 0 (Default/DF) - No marking
- `tos 0x28` = DSCP 10 (AF11) - 0x28 = 40 decimal = (10 << 2)
- `tos 0xb8` = DSCP 46 (EF) - 0xb8 = 184 decimal = (46 << 2)

#### Option B: Capture on the Worker Node

Capture traffic as it leaves the pod's network namespace:

```bash
# Terminal 1: Capture on worker node
sudo docker exec -it clab-calico-dscp-k01-worker tcpdump -i eth1 -v -n 'ip' -c 20

# Terminal 2: Generate traffic
kubectl exec -it sender-dscp-af11 -- ping -c 5 10.30.30.100
```

#### Option C: Capture on the Client

Capture incoming traffic on the client:

```bash
# Terminal 1: Capture on client
sudo docker exec -it clab-calico-dscp-client tcpdump -i eth1 -v -n 'ip' -c 20

# Terminal 2: Generate traffic
kubectl exec -it sender-dscp-af11 -- ping -c 5 10.30.30.100
```

#### Using tcpdump Filters for Specific DSCP Values

Filter for specific DSCP values:

```bash
# Capture only AF11 (DSCP 10, TOS 0x28) traffic
sudo docker exec -it clab-calico-dscp-router tcpdump -i eth3 -v -n 'ip[1] & 0xfc == 0x28'

# Capture only EF (DSCP 46, TOS 0xb8) traffic  
sudo docker exec -it clab-calico-dscp-router tcpdump -i eth3 -v -n 'ip[1] & 0xfc == 0xb8'

# Capture unmarked traffic (DSCP 0)
sudo docker exec -it clab-calico-dscp-router tcpdump -i eth3 -v -n 'ip[1] & 0xfc == 0x00'
```

> **Note**: The TOS byte includes DSCP (6 bits) + ECN (2 bits). The filter `ip[1] & 0xfc` masks out the ECN bits (lower 2 bits) to match only the DSCP value.

#### Comparing Marked vs Unmarked Traffic

Compare traffic from different pods:

```bash
# Terminal 1: Start capture
sudo docker exec -it clab-calico-dscp-router tcpdump -i eth3 -v -n 'ip' | grep -E "(tos|sender)"

# Terminal 2: Test unmarked pod
kubectl exec -it sender-no-dscp -- ping -c 3 10.30.30.100

# Terminal 3: Test AF11-marked pod
kubectl exec -it sender-dscp-af11 -- ping -c 3 10.30.30.100

# Terminal 4: Test EF-marked pod
kubectl exec -it sender-dscp-ef -- ping -c 3 10.30.30.100
```

You should see different `tos` values for each pod:
- `sender-no-dscp`: `tos 0x00`
- `sender-dscp-af11`: `tos 0x28`
- `sender-dscp-ef`: `tos 0xb8`

### 9. Inspect Linux Router QoS Configuration

## Results Summary

| Pod | DSCP Value | Router Policy | Observed Bandwidth |
|-----|------------|---------------|-------------------|
| sender-no-dscp | 0 (DF) | No limit | ~1 Gbps |
| sender-dscp-af11 | 10 (AF11) | 1 Mbps (Linux tc) | ~1 Mbps |
| sender-dscp-ef | 46 (EF) | 5 Mbps (Linux tc) | ~5 Mbps |

## Key Concepts

### Calico DSCP Annotation

```yaml
metadata:
  annotations:
    qos.projectcalico.org/dscp: "AF11"
```

- Applied to pod metadata
- Marks **all egress traffic** from the pod
- Supports numeric (0-63) or named values (AF11, EF, CS3, etc.)

### Linux Router QoS (tc)

Since containerized Arista cEOS doesn't support DSCP matching, we use Linux `tc` (traffic control) on a Linux router:

```bash
# HTB (Hierarchical Token Bucket) qdisc
tc qdisc add dev eth1 root handle 1: htb default 30

# Classes for different DSCP values
tc class add dev eth1 parent 1:1 classid 1:10 htb rate 1mbit ceil 1mbit  # AF11
tc class add dev eth1 parent 1:1 classid 1:20 htb rate 5mbit ceil 5mbit  # EF
tc class add dev eth1 parent 1:1 classid 1:30 htb rate 1000mbit         # Default

# Filters matching TOS byte (DSCP << 2)
tc filter add dev eth1 protocol ip parent 1:0 prio 1 u32 match ip tos 0x28 0xff flowid 1:10  # AF11
tc filter add dev eth1 protocol ip parent 1:0 prio 2 u32 match ip tos 0xb8 0xff flowid 1:20  # EF
```

- HTB qdisc provides hierarchical rate limiting
- Classes define bandwidth limits for each DSCP value
- Filters match packets based on TOS byte (DSCP value shifted left by 2 bits)

### Network Routing

This lab uses a simple Linux router for connectivity:

- **Router IPs**: 
  - `10.10.10.1/24` (facing cluster nodes)
  - `10.30.30.1/24` (facing client)
- **Static Routes**: Nodes and client use static routes via the router
- **IP Forwarding**: Enabled on the router to forward traffic between networks

The router performs both routing and DSCP-based QoS throttling using Linux `tc`, demonstrating how network devices can classify and throttle traffic based on DSCP markings.

### DSCP Preservation

DSCP markings set by Calico are preserved across the network path as long as:
- Network devices don't explicitly rewrite DSCP
- Traffic doesn't cross trust boundaries that reset DSCP

## Cleanup

```bash
chmod +x destroy.sh
./destroy.sh
```

Or follow **[Lab cleanup](../readme.md#lab-cleanup)**
