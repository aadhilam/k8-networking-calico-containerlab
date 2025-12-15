# Calico WireGuard Encryption

This lab demonstrates Calico's WireGuard encryption feature for securing pod-to-pod traffic between nodes. You'll see the clear difference between unencrypted and encrypted traffic using packet captures.

## Why WireGuard Encryption?

In Kubernetes environments, pod-to-pod traffic between nodes traverses the physical network infrastructure. Without encryption, this traffic is vulnerable to:

- **Eavesdropping**: Network administrators or attackers can capture and read pod traffic
- **Man-in-the-Middle Attacks**: Traffic can be intercepted and modified
- **Compliance Violations**: Many regulations require encryption of data in transit

Calico's WireGuard integration provides:

| Feature | Benefit |
|---------|---------|
| **Transparent Encryption** | No application changes required |
| **High Performance** | WireGuard is faster than IPsec |
| **Simple Configuration** | Enable with a single command |
| **Automatic Key Management** | Wireguard handles key rotation |

## How WireGuard Works with Calico

When WireGuard is enabled:

1. **Key Generation**: Each node generates a WireGuard key pair
2. **Peer Discovery**: Calico automatically configures WireGuard peers between nodes
3. **Tunnel Creation**: A `wireguard.cali` interface is created on each node
4. **Traffic Encryption**: All pod-to-pod traffic between nodes is encrypted via UDP port 51820

**Without WireGuard:**
```
Pod A (Node 1) → [Plain/VXLAN packet] → Physical Network → [Plain/VXLAN packet] → Pod B (Node 2)
                     ↑ Readable by anyone on the network
```

**With WireGuard:**
```
Pod A (Node 1) → [Encrypted WireGuard packet] → Physical Network → [Encrypted packet] → Pod B (Node 2)
                     ↑ Encrypted - unreadable without keys
```

## WireGuard Key Exchange and Cryptography

WireGuard uses modern cryptographic primitives and a simple key exchange mechanism. Understanding this helps explain how encryption and decryption work between nodes.

### Key Types

Each node has a **public/private key pair**:

| Key Type | Purpose | Storage |
|----------|---------|---------|
| **Private Key** | Used to decrypt incoming traffic and sign outgoing traffic | Kept secret on the node |
| **Public Key** | Shared with peers to encrypt traffic destined for this node | Distributed via Calico datastore |

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     KEY PAIRS PER NODE                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   wireguard-worker                        wireguard-worker2              │
│  ┌────────────────────┐                 ┌────────────────────┐           │
│  │ Private Key: [A]   │                 │ Private Key: [B]   │           │
│  │ (kept secret)      │                 │ (kept secret)      │           │
│  │                    │                 │                    │           │
│  │ Public Key: [A']   │◄───────────────►│ Public Key: [B']   │           │
│  │ (shared with peers)│   Key Exchange  │ (shared with peers)│           │
│  └────────────────────┘                 └────────────────────┘           │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### How Key Exchange Works

WireGuard uses the **Noise Protocol Framework** (specifically Noise_IKpsk2) for key exchange:

1. **Static Keys**: Each node generates a long-term key pair (Curve25519)
2. **Ephemeral Keys**: For each handshake, temporary keys are generated for forward secrecy
3. **Session Keys**: The handshake derives symmetric session keys for actual data encryption

```mermaid
flowchart LR
    subgraph Node1["wireguard-worker"]
        PK1[Public Key A']
        SK1[Private Key A]
    end
    
    subgraph Handshake["Key Exchange"]
        direction TB
        H1[1. Initiator sends<br/>encrypted handshake<br/>with ephemeral key]
        H2[2. Responder replies<br/>with its ephemeral key]
        H3[3. Session keys<br/>derived]
        H1 --> H2
        H2 --> H3
    end
    
    subgraph Node2["wireguard-worker2"]
        PK2[Public Key B']
        SK2[Private Key B]
    end
    
    Node1 --> Handshake
    Handshake --> Node2
    
    style H1 fill:#FF9800,color:white
    style H2 fill:#FF9800,color:white
    style H3 fill:#4CAF50,color:white
```

### Encryption and Decryption Flow

| Direction | Encryption Key Used | Decryption Key Used |
|-----------|---------------------|---------------------|
| Node A → Node B | Session key derived from A's private + B's public | Session key on Node B |
| Node B → Node A | Session key derived from B's private + A's public | Session key on Node A |

**Detailed Flow:**

```
╔═════════════════════════════════════════════════════════════════════════════╗
║                       ENCRYPTION/DECRYPTION FLOW                            ║
╠═════════════════════════════════════════════════════════════════════════════╣
║                                                                             ║
║  ┌─────────────────────────────────────────────────────────────────────┐    ║
║  │  SENDING (Node A → Node B)                                          │    ║
║  ├─────────────────────────────────────────────────────────────────────┤    ║
║  │                                                                     │    ║
║  │   1. Plaintext packet (HTTP request with passwords, tokens)         │    ║
║  │                              ↓                                      │    ║
║  │   2. WireGuard encrypts using:                                      │    ║
║  │      • Session key (derived from ECDH of A's private + B's public)  │    ║
║  │      • ChaCha20-Poly1305 cipher                                     │    ║
║  │                              ↓                                      │    ║
║  │   3. Encrypted packet sent via UDP port 51820                       │    ║
║  │                                                                     │    ║
║  └─────────────────────────────────────────────────────────────────────┘    ║
║                                                                             ║
║  ┌─────────────────────────────────────────────────────────────────────┐    ║
║  │  RECEIVING (on Node B)                                              │    ║
║  ├─────────────────────────────────────────────────────────────────────┤    ║
║  │                                                                     │    ║
║  │   4. Encrypted packet received on UDP 51820                         │    ║
║  │                              ↓                                      │    ║
║  │   5. WireGuard decrypts using:                                      │    ║
║  │      • Session key (derived from ECDH of B's private + A's public)  │    ║
║  │      • ChaCha20-Poly1305 cipher                                     │    ║
║  │                              ↓                                      │    ║
║  │   6. Original plaintext packet delivered to pod                     │    ║
║  │                                                                     │    ║
║  └─────────────────────────────────────────────────────────────────────┘    ║
║                                                                             ║
╚═════════════════════════════════════════════════════════════════════════════╝
```

### Cryptographic Primitives

WireGuard uses a fixed set of modern, high-performance cryptographic algorithms:

| Component | Algorithm | Purpose |
|-----------|-----------|---------|
| **Key Exchange** | Curve25519 (ECDH) | Generate shared secrets |
| **Encryption** | ChaCha20 | Encrypt packet payload |
| **Authentication** | Poly1305 | Authenticate packets (prevent tampering) |
| **Hashing** | BLAKE2s | Key derivation and hashing |

**Detailed Cryptographic Flow:**

```
╔═══════════════════════════════════════════════════════════════════════════════════════════════════╗
║  PHASE 1: THE HANDSHAKE (Generating the Keys)                                                     ║
║  Runs every few minutes to create a fresh encryption key                                          ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════╝
+--------------+-----------------------+----------------------------------+-------------------------+
|  PRIMITIVE   |         ROLE          |           EXACT INPUTS           |      EXACT OUTPUT       |
+--------------+-----------------------+----------------------------------+-------------------------+
|              | Key Exchange          | 1. Local Private Key (Static)    |                         |
|  Curve25519  | (ECDH)                | 2. Remote Public Key (Static)    | Raw Shared Secret       |
|              | *See "Recipe" below   | 3. Ephemeral Private Key (Rand)  | (32 bytes)              |
|              | for detailed steps    | 4. Ephemeral Public Key (Remote) |                         |
+--------------+-----------------------+----------------------------------+-------------------------+
|              |                       | 1. Raw Shared Secret (from Step1)|                         |
|  BLAKE2s     | Key Derivation        | 2. Protocol Context Strings      | Session Key             |
|              | (HKDF)                | 3. Handshake Hash (Transcript)   | (32 bytes)              |
|              |                       |                                  |                         |
+--------------+-----------------------+----------------------------------+-------------------------+

╔═══════════════════════════════════════════════════════════════════════════════════════════════════╗
║  THE "RECIPE": How the Session Key is Made                                                        ║
║  WireGuard uses HKDF to mix several DH operations into the final Session Key                      ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                   ║
║  Note: Both Static and Ephemeral keys are Curve25519 key PAIRS (private + public).                ║
║  • Static keys    → Long-term identity, stored on the node                                        ║
║  • Ephemeral keys → Fresh random keys generated per handshake, public keys exchanged in messages  ║
║  • Both use Curve25519: 32-byte random private key → derives 32-byte public key                   ║
║                                                                                                   ║
║  ╭─────────────────────────┬─────────────────────────────────────────────────────────────────╮    ║
║  │  DH COMBINATION         │  PURPOSE                                                        │    ║
║  ├─────────────────────────┼─────────────────────────────────────────────────────────────────┤    ║
║  │                         │                                                                 │    ║
║  │  Ephemeral + Ephemeral  │  ★ Forward Secrecy                                              │    ║
║  │  (Your Random Key +     │    Even if long-term keys are compromised later, past           │    ║
║  │   Server's Random Key)  │    sessions remain secure (ephemeral keys are discarded)        │    ║
║  │                         │                                                                 │    ║
║  ├─────────────────────────┼─────────────────────────────────────────────────────────────────┤    ║
║  │                         │                                                                 │    ║
║  │  Ephemeral + Static     │  ★ Secrecy                                                      │    ║
║  │  (Your Random Key +     │    Ensures only the server (who owns the static private         │    ║
║  │   Server's Identity Key)│    key) can decrypt your ephemeral contribution                 │    ║
║  │                         │                                                                 │    ║
║  ├─────────────────────────┼─────────────────────────────────────────────────────────────────┤    ║
║  │                         │                                                                 │    ║
║  │  Static + Ephemeral     │  ★ Response Security                                            │    ║
║  │  (Your Identity Key +   │    Ensures that the server's response can only be decrypted     │    ║
║  │   Server's Random Key)  │    by you (confidentiality for the client)                      │    ║
║  │                         │                                                                 │    ║
║  ├─────────────────────────┼─────────────────────────────────────────────────────────────────┤    ║
║  │                         │                                                                 │    ║
║  │  Static + Static        │  ★ Mutual Authentication                                        │    ║
║  │  (Your Identity Key +   │    Cryptographically binds the session to the static identities │    ║
║  │   Server's Identity Key)│    of both peers (Authentication)                               │    ║
║  │                         │                                                                 │    ║
║  ╰─────────────────────────┴─────────────────────────────────────────────────────────────────╯    ║
║                                                                                                   ║
║  All four DH results are mixed together via HKDF to produce the final Session Key                 ║
║                                                                                                   ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════╝

╔═══════════════════════════════════════════════════════════════════════════════════════════════════╗
║  PHASE 2: TRANSPORT (Protecting the Packet)                                                       ║
║  Runs for every single data packet sent over the tunnel                                           ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════╝
+--------------+-----------------------+----------------------------------+-------------------------+
|              |                       | 1. Session Key (from Phase 1)    | 1. Ciphertext           |
|  ChaCha20    | Encryption            | 2. Packet Counter (Nonce)        |    (Encrypted Data)     |
|              | (Stream Cipher)       | 3. Plaintext (Inner IP Packet)   | 2. One-Time Key         |
|              |                       |                                  |    (for Poly1305)       |
+--------------+-----------------------+----------------------------------+-------------------------+
|              |                       | 1. One-Time Key (from ChaCha20)  |                         |
|  Poly1305    | Authentication        | 2. Ciphertext (Encrypted Data)   | Authentication Tag      |
|              | (MAC)                 | 3. WG Header (Type, Index, etc.) | (16 bytes)              |
|              |                       |                                  |                         |
+--------------+-----------------------+----------------------------------+-------------------------+
```



### Viewing Keys in the Lab

You can view the public keys for each node:

```bash
# View public key for wireguard-worker
docker exec -it wireguard-worker wg show wireguard.cali public-key

# View all peer information including their public keys
docker exec -it wireguard-worker wg show wireguard.cali
```

## Lab Architecture

This lab deploys a realistic microservices scenario:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         MICROSERVICES DEMO                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   wireguard-worker                      wireguard-worker2                │
│  ┌──────────────────┐                  ┌──────────────────┐              │
│  │  frontend-client │ ──HTTP+Auth───▶  │   backend-api    │              │
│  │                  │                  │                  │              │
│  │  Sends requests  │                  │  Returns:        │              │
│  │  with:           │                  │  - User passwords│              │
│  │  - JWT tokens    │                  │  - AWS keys      │              │
│  │  - API keys      │                  │  - DB credentials│              │
│  │  - Session cookies│                 │  - Stripe keys   │              │
│  └──────────────────┘                  └──────────────────┘              │
│                                                                          │
│              ▲                                    ▲                       │
│              │        Physical Network           │                       │
│              └────────────────┬──────────────────┘                       │
│                               │                                          │
│                    WITHOUT WIREGUARD:                                    │
│                    All this data is visible!                             │
└─────────────────────────────────────────────────────────────────────────┘
```

The `frontend-client` continuously sends HTTP requests containing:
- JWT Bearer tokens
- API keys
- Session cookies
- Basic auth credentials

The `backend-api` responds with sensitive data:
- User passwords
- AWS access keys
- Database connection strings
- Stripe API keys

## Lab Setup

To setup the lab for this module **[Lab setup](../README.md#lab-setup)**
The lab folder is - `/containerlab/13-wireguard`

## Deployment

The `deploy.sh` script automates the complete lab setup:

1. **ContainerLab Topology Deployment**: Creates a 3-node Kind cluster (1 control-plane, 2 workers)
2. **Kubeconfig Setup**: Exports the Kind cluster's kubeconfig
3. **Calico Installation**: Deploys Calico CNI with VXLAN encapsulation (no encryption initially)
4. **Microservices Deployment**: Deploys frontend and backend pods on different nodes
5. **tcpdump Installation**: Installs tcpdump on worker nodes for packet capture

Deploy the lab:
```bash
cd containerlab/13-wireguard
chmod +x deploy.sh
./deploy.sh
```

## Lab Exercises

### 1. Verify the Lab Setup

```bash
# Set kubeconfig
export KUBECONFIG=$(pwd)/wireguard.kubeconfig

# Check nodes
kubectl get nodes -o wide
```

##### Expected output
```
NAME                    STATUS   ROLES           AGE   VERSION
wireguard-control-plane Ready    control-plane   5m    v1.28.0
wireguard-worker        Ready    <none>          5m    v1.28.0
wireguard-worker2       Ready    <none>          5m    v1.28.0
```

##### command
```bash
# Check pods - ensure they're on different nodes
kubectl get pods -o wide
```

##### Expected output
```
NAME               READY   STATUS    RESTARTS   AGE   IP               NODE               
frontend-client    1/1     Running   0          2m    192.168.183.65   wireguard-worker   
backend-api        1/1     Running   0          2m    192.168.140.65   wireguard-worker2  
```

> [!IMPORTANT]
> The pods must be on **different nodes** for this lab to work. WireGuard encrypts traffic between nodes, not within the same node. If both pods are on the same node, delete and recreate them until they land on different nodes.

### 2. Verify Current Encryption Status (None)

First, let's confirm that WireGuard is NOT enabled:

##### command
```bash
kubectl get felixconfiguration default -o yaml | grep -i wireguard
```

##### Expected output
```
(no output - WireGuard not configured)
```

##### command
```bash
# Check if wireguard interface exists on a node (it shouldn't)
docker exec -it wireguard-worker ip link show type wireguard
```

##### Expected output
```
(no output or error - no WireGuard interface)
```

### 3. Capture Unencrypted Traffic (Before WireGuard)

Now let's demonstrate that without WireGuard, we can see the pod traffic in plain text. The frontend is **continuously sending requests**, so you just need to capture!

#### 3.1 - Capture Traffic with Sensitive Data

Run this command to see passwords, API keys, and tokens flowing in plain text:

##### command
```bash
docker exec -it wireguard-worker2 tcpdump -Z root -i eth0 -A 2>/dev/null | grep -E --color=always 'password|secret|Bearer|API-Key|aws_|stripe_'
```

##### Expected output (sensitive data visible!)
```
"password": "xxx"
Authorization: Bearer eyJxxx.xxx.xxx
X-API-Key: sk_live_xxx
"aws_access_key": "AKIAxxx"
"aws_secret_key": "xxx"
"stripe_api_key": "sk_live_xxx"
```

**This is the security problem!** Anyone with network access can see:
- User passwords in API responses
- JWT tokens and API keys
- AWS credentials
- Database connection strings with passwords

Press `Ctrl+C` to stop the capture.

#### 3.2 - View Full HTTP Requests and Responses

To see more context around the sensitive data:

##### command
```bash
docker exec -it wireguard-worker2 timeout 10 tcpdump -Z root -i eth0 -A 2>/dev/null | head -150
```

You'll see full HTTP requests with headers like `Authorization: Bearer ...` and JSON responses containing passwords and API keys.

### 4. Enable WireGuard Encryption

Now let's enable WireGuard to encrypt all inter-node pod traffic.

#### 4.1 - Enable WireGuard via FelixConfiguration

##### command
```bash
kubectl patch felixconfiguration default --type='merge' -p '{"spec":{"wireguardEnabled":true}}'
```

##### Expected output
```
felixconfiguration.crd.projectcalico.org/default patched
```

#### 4.2 - Verify WireGuard is Enabled

##### command
```bash
kubectl get felixconfiguration default -o yaml | grep -i wireguard
```

##### Expected output
```
  wireguardEnabled: true
```

#### 4.3 - Wait for WireGuard Interface to be Created

It takes a few seconds for Calico to create the WireGuard interfaces on each node.

##### command
```bash
# Check for wireguard interface on worker node
docker exec -it wireguard-worker ip link show type wireguard
```

##### Expected output
```
10: wireguard.cali: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1440 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
    link/none
```

#### 4.4 - View WireGuard Configuration

##### command
```bash
# Show WireGuard peers and configuration
docker exec -it wireguard-worker wg show
```

##### Expected output
```
interface: wireguard.cali
  public key: aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567890abcdefg=
  private key: (hidden)
  listening port: 51820
  fwmark: 0x100000

peer: xYz987654321AbCdEfGhIjKlMnOpQrStUvWxYz098765=
  endpoint: 172.18.0.3:51820
  allowed ips: 192.168.140.64/26, 172.18.0.3/32
  latest handshake: 5 seconds ago
  transfer: 1.24 KiB received, 1.56 KiB sent
```

**Key Observations:**
- **wireguard.cali** interface is created
- **Public/private keys** are automatically generated
- **Listening port 51820** (WireGuard's standard port)
- **Peers** are automatically configured for other nodes
- **Allowed IPs** include pod CIDRs and node IPs.
  > **Note on Configuration:** Calico's **Felix** agent automatically configures these Allowed IPs. It calculates them to include the remote node's Pod CIDR (e.g., `192.168.140.64/26`) and the node's internal IP (e.g., `172.18.0.3/32`), ensuring traffic destined for those networks is routed through the tunnel. You do not need to manually configure peers or routes.


### 5. Capture Encrypted Traffic (After WireGuard)

Now let's see the difference with WireGuard enabled!

#### 5.1 - Try to Capture Sensitive Data (It's Encrypted!)

Run the same tcpdump grep command as before:

##### command
```bash
docker exec -it wireguard-worker2 timeout 15 tcpdump -Z root -i eth0 -A 2>/dev/null | grep -E 'password|secret|Bearer|API-Key|aws_|stripe_'
```

##### Expected output
```
(no output - the sensitive data is encrypted!)
```

**The passwords, API keys, and tokens are no longer visible!**

#### 5.2 - View the Encrypted WireGuard Packets

##### command
```bash
docker exec -it wireguard-worker2 tcpdump -Z root -i eth0 -c 10 'udp port 51820' 2>/dev/null
```

##### Expected output (just encrypted UDP packets)
```
15:45:23.456789 IP 172.18.0.2.51820 > 172.18.0.3.51820: UDP, length 132
15:45:23.457012 IP 172.18.0.3.51820 > 172.18.0.2.51820: UDP, length 132
15:45:24.458234 IP 172.18.0.2.51820 > 172.18.0.3.51820: UDP, length 196
15:45:24.458567 IP 172.18.0.3.51820 > 172.18.0.2.51820: UDP, length 548
```

#### 5.3 - Try to Read the Payload (It's Unreadable!)

##### command
```bash
docker exec -it wireguard-worker2 timeout 5 tcpdump -Z root -i eth0 -A 'udp port 51820' 2>/dev/null | head -30
```

##### Expected output (encrypted binary garbage)
```
E....."@.@........#...........
.J..z..K.n..Q.x.*.......m..H.W..
..3.s.....R......j.K.Y..8.L....
(completely unreadable encrypted data)
```

**Key Observations:**
- Traffic now uses **UDP port 51820** (WireGuard)
- **NO passwords visible** - everything is encrypted
- **NO API keys visible** - everything is encrypted
- **NO HTTP headers visible** - everything is encrypted
- The payload is **completely unreadable**!

### 6. Traffic Comparison Summary

| Aspect | Without WireGuard | With WireGuard |
|--------|-------------------|----------------|
| **Encapsulation** | VXLAN (UDP 4789) | WireGuard (UDP 51820) |
| **Passwords Visible** | Yes (e.g. `xxx`) | No (encrypted) |
| **API Keys Visible** | Yes (e.g. `sk_live_xxx`) | No (encrypted) |
| **JWT Tokens Visible** | Yes (e.g. `Bearer eyJxxx`) | No (encrypted) |
| **AWS Credentials Visible** | Yes (e.g. `AKIAxxx`) | No (encrypted) |
| **HTTP Headers Visible** | Yes | No (encrypted) |

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     TRAFFIC COMPARISON                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  WITHOUT WireGuard (VXLAN):                                             │
│  ┌─────────────────────────────────────────────────────────────┐        │
│  │ Outer IP │ UDP 4789 │ VXLAN │ HTTP Request + Auth Headers   │        │
│  │ Header   │ Header   │ Header│ + Passwords + API Keys        │        │
│  └─────────────────────────────────────────────────────────────┘        │
│       ↑          ↑         ↑                    ↑                       │
│    Visible   Visible   Visible          ALL VISIBLE!                    │
│                                                                         │
│  WITH WireGuard:                                                        │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │ Outer IP │ UDP 51820 │         ENCRYPTED PAYLOAD                  │  │
│  │ Header   │ Header    │  (HTTP, passwords, keys all encrypted)     │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│       ↑          ↑                        ↑                             │
│    Visible   Visible              Completely Hidden                     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

WireGuard Packet Structure (detailed):
┌──────────┬──────────┬─────────────────────────────────────────────────────┐
│ IP Header│UDP Header│              WireGuard Payload                      │
│ 20 bytes │ 8 bytes  │                                                     │
├──────────┴──────────┼────────┬────────┬─────────┬─────────┬───────┬──────┤
│      Visible        │ Type   │Reserved│Receiver │ Counter │Encrypt│ Auth │
│   (IPs + Port)      │1 byte  │3 bytes │Index    │ 8 bytes │ Data  │ Tag  │
│                     │        │        │4 bytes  │         │(var)  │16 B  │
└─────────────────────┴────────┴────────┴─────────┴─────────┴───────┴──────┘
```

### 7. Verify Routing Changes

WireGuard changes how traffic is routed between nodes. When enabled, Calico creates a `wireguard.cali` interface and updates the routing table so that traffic destined for pods on other nodes goes through the encrypted WireGuard tunnel.

```mermaid
flowchart LR
    subgraph Node1["wireguard-worker"]
        Pod1[frontend-client]
        WG1[wireguard.cali<br/>Encrypt]
    end
    
    subgraph Network[" "]
        Wire[Encrypted UDP<br/>Port 51820]
    end
    
    subgraph Node2["wireguard-worker2"]
        WG2[wireguard.cali<br/>Decrypt]
        Pod2[backend-api]
    end
    
    Pod1 -->|HTTP + Creds| WG1
    WG1 -->|Encrypted| Wire
    Wire -->|Encrypted| WG2
    WG2 -->|HTTP + Creds| Pod2
    
    style WG1 fill:#4CAF50,color:white
    style WG2 fill:#4CAF50,color:white
    style Pod1 fill:#2196F3,color:white
    style Pod2 fill:#2196F3,color:white
    style Wire fill:#FF9800,color:white
```

**How WireGuard Routing Works:**

1. **Pod sends packet** - frontend-client sends HTTP request to backend-api (192.168.140.65)
2. **Route lookup** - Kernel checks routing table for destination
3. **WireGuard route match** - Route `192.168.140.64/26 via wireguard.cali` matches
4. **Encryption** - WireGuard encrypts the entire packet and wraps it in UDP (port 51820)
5. **Network transit** - Encrypted packet travels over physical network
6. **Reception** - Destination node receives UDP packet on port 51820
7. **Decryption** - WireGuard decrypts and extracts original packet
8. **Local routing** - Packet is routed to local pod via veth interface
9. **Delivery** - backend-api receives the original HTTP request

##### command
```bash
# View routes on worker node - traffic to other nodes goes via wireguard.cali
docker exec -it wireguard-worker ip route | grep -E "wireguard|192.168"
```

##### Expected output
```
192.168.140.64/26 via 172.18.0.3 dev wireguard.cali onlink
192.168.166.128/26 via 172.18.0.4 dev wireguard.cali onlink
blackhole 192.168.183.64/26 proto 80
```

**Key Observation:** Routes to other nodes' pod CIDRs now go through `wireguard.cali` instead of `eth0` or `vxlan.calico`.

### 8. Disable WireGuard (Optional)

To disable WireGuard and return to unencrypted traffic:

##### command
```bash
kubectl patch felixconfiguration default --type='merge' -p '{"spec":{"wireguardEnabled":false}}'
```

##### Verify
```bash
# WireGuard interface should disappear after a few seconds
docker exec -it wireguard-worker ip link show type wireguard
```

After disabling, you can run the tcpdump grep command again and see the sensitive data is once again visible!

## Summary

This lab demonstrated Calico's WireGuard encryption with a realistic microservices scenario:

| Aspect | Before WireGuard | After WireGuard |
|--------|------------------|-----------------|
| **Configuration** | VXLAN only | Single kubectl patch |
| **Passwords** | Visible in tcpdump | Encrypted |
| **API Keys** | Visible in tcpdump | Encrypted |
| **JWT Tokens** | Visible in tcpdump | Encrypted |
| **Port Used** | UDP 4789 | UDP 51820 |
| **Key Management** | N/A | Automatic |

**Key Takeaways:**

1. **Real Security Risk**: Without encryption, sensitive data (passwords, API keys, tokens) flows in plain text
2. **Easy to Enable**: Single command to enable encryption cluster-wide
3. **Transparent**: No application changes required
4. **Automatic Key Management**: Calico handles key generation and distribution
5. **Verifiable**: You can see the encryption working via packet captures
6. **Production Ready**: WireGuard is proven, high-performance encryption

## Troubleshooting

### WireGuard Interface Not Created

If the `wireguard.cali` interface doesn't appear:

```bash
# Check Felix logs
kubectl logs -n calico-system -l k8s-app=calico-node --tail=50 | grep -i wireguard

# Check if WireGuard kernel module is loaded
docker exec -it wireguard-worker lsmod | grep wireguard
```

### Traffic Still Using VXLAN

If traffic still goes through VXLAN after enabling WireGuard:

```bash
# Restart calico-node pods to pick up the change
kubectl rollout restart daemonset -n calico-system calico-node

# Wait for pods to restart
kubectl rollout status daemonset -n calico-system calico-node
```

### WireGuard Not Supported

WireGuard requires kernel support. If you see errors:

```bash
# Check kernel version (needs 5.6+ or backported module)
docker exec -it wireguard-worker uname -r

# Check for wireguard module
docker exec -it wireguard-worker modprobe wireguard
```

## Additional Notes

### Performance Considerations

WireGuard is designed for high performance:
- Uses modern cryptographic primitives (ChaCha20, Poly1305, Curve25519)
- Kernel-based implementation (faster than userspace IPsec)
- Typical overhead: 5-10% for most workloads

### IPv6 Support

Calico also supports WireGuard for IPv6 traffic:
```bash
kubectl patch felixconfiguration default --type='merge' -p '{"spec":{"wireguardEnabledV6":true}}'
```

### Statistics

View WireGuard statistics:
```bash
# Per-peer transfer statistics
docker exec -it wireguard-worker wg show wireguard.cali transfer
```

## Lab Cleanup

To cleanup the lab follow steps in **[Lab cleanup](../README.md#lab-cleanup)**

Or run:
```bash
chmod +x destroy.sh
./destroy.sh
```
