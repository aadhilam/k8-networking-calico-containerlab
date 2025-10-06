# Calico Multiple IPPools

This lab demonstrates how multiple IP pools can be configured in Calico.

## Lab Setup
To setup the lab for this module **[Lab setup](../readme.md#lab-setup)**
The lab folder is - `/containerlab/9-multi-ippool


## Lab

### 1. Inspect ContainerLab Topology

First, let's inspect the lab topology.

##### command
```bash
containerlab inspect topology.clab.yaml 
```

export KUBECONFIG=/home/ubuntu/containerlab/9-multi-ippool/k01.kubeconfig


> [!Note]
> <mark> We are utilizing the same lab topology as the previous BGP lab that can be found here **[Lab setup](../8-calico-bgp-lb/README.md)** <mark>

