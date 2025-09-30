# Calico Overlay Lab with FRR

This lab demonstrates Calico networking with BGP peering using FRRouting (FRR) instead of Arista cEOS. This is a replication of the `calico-lab-1` setup but using FRR as the BGP peer.

## Architecture

The lab consists of:
- **FRR Router (frr01)**: BGP AS 65001, acts as a BGP peer for Calico nodes
- **Kubernetes Cluster**: 3-node Kind cluster with Calico CNI
  - Control plane: `10.10.10.100`
  - Worker 1: `10.10.10.101` 
  - Worker 2: `10.10.10.102`

## Network Details

- **Management Network**: `10.10.10.0/24`
- **Pod Network**: `10.0.0.0/16` (Calico managed)
- **Service Network**: `10.1.0.0/16`
- **BGP AS Numbers**:
  - FRR Router: AS 65001
  - Calico nodes: AS 65010

## Key Differences from calico-lab-1

1. **Router Platform**: Uses FRR instead of Arista cEOS
2. **Configuration**: FRR configuration in `containerlab/r0/frr.conf`
3. **BGP Peer**: Updated BGP peer configuration to point to FRR router

## Files Structure

```
calico-overlay/
├── README.md                           # This file
├── deploy.sh                          # Deployment script
├── destroy.sh                         # Cleanup script
├── k01-no-cni.yaml                   # Kind cluster config (no CNI)
├── containerlab/
│   ├── topology.clab.yaml            # ContainerLab topology
│   ├── k01-no-cni.yaml              # Kind cluster config
│   └── r0/
│       ├── daemons                    # FRR daemons config
│       └── frr.conf                   # FRR BGP configuration
└── calico-cni-config/
    ├── custom-resources.yaml          # Calico installation config
    ├── bgpconfiguration.yaml          # Calico BGP settings
    └── bgppeer.yaml                   # BGP peer definition
```

## Usage

### Deploy the Lab

```bash
chmod +x deploy.sh
./deploy.sh
```

### Monitor BGP Status

Check FRR BGP status:
```bash
sudo docker exec clab-calico-overlay-frr01 vtysh -c "show bgp summary"
sudo docker exec clab-calico-overlay-frr01 vtysh -c "show ip route bgp"
```

Check Calico BGP status:
```bash
export KUBECONFIG=$(pwd)/k01.kubeconfig
calicoctl node status
kubectl get nodes -o wide
```

### Destroy the Lab

```bash
chmod +x destroy.sh  
./destroy.sh
```

## BGP Configuration

The FRR router is configured to:
- Listen for BGP connections from the `10.10.10.0/24` subnet
- Peer with Calico nodes using AS 65010
- Advertise the management network `10.10.10.0/24`

Calico is configured to:
- Use AS 65010 for all nodes
- Disable node-to-node mesh (rely on external BGP peer)
- Peer with FRR router at `10.10.10.1` (AS 65001)

## Troubleshooting

1. **Check container status**: `sudo containerlab inspect -t containerlab/topology.clab.yaml`
2. **Check Kind cluster**: `kubectl get nodes`
3. **Check Calico pods**: `kubectl get pods -n calico-system`
4. **Check BGP sessions**: Use the monitoring commands above