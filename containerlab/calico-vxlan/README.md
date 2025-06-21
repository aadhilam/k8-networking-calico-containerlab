# Exploring ContainerLab Setup

This package replicates the simple exploration topology from the VirtualizeStuff article **“Exploring ContainerLab.”**

## Components

| File | Purpose |
|------|---------|
| `topology.yaml` | Containerlab topology (1 FRR router + 3 Linux nodes) |
| `configs/r0/frr.conf` | Basic FRR startup‑config enabling OSPF between r0 and all nodes |
| `deploy.sh` | Convenience script to stand the lab up |
| `destroy.sh` | Convenience script to tear the lab down |

## Quick start

```bash
# install containerlab first
curl -sL https://get.containerlab.dev | sudo bash

# optional: install kind if you wish to turn the linux nodes into Kubernetes workers
brew install kind # or follow upstream docs

# clone, unzip or download this bundle
unzip containerlab_exploring_setup.zip
cd containerlab_exploring_setup

# deploy
./deploy.sh

# verify
containerlab inspect -t topology.yaml

# when finished
./destroy.sh
```

> **Tip**  The three `linux` nodes ship with the standard “kind” base image.  
> You can `kind create cluster --name demo --image kindest/node:v1.30.0 --config kind.yaml` and then join the nodes to r0 to test CNI behaviour exactly as shown in the blog post.