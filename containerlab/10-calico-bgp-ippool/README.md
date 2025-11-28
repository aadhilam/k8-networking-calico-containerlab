# Calico Advertise IPPool Using BGP
#TODO add a 2 sentence introduction to this lab



## Lab Setup
To setup the lab for this module **[Lab setup](../readme.md#lab-setup)**
The lab folder is - `/containerlab/10-multi-ippool`




## Lab





docker exec -it clab-calico-bgp-lb-ceos01 Cli

docker exec -it k01-control-plane  /bin/bash
docker exec -it k01-worker3  /bin/bash


kubectl apply -f -<<EOF
apiVersion: projectcalico.org/v3
kind: CalicoNodeStatus
metadata:
  name: k01-control-plane
spec:
  classes:
    - Agent
    - BGP
    - Routes
  node: k01-control-plane
  updatePeriodSeconds: 10
EOF


kubectl apply -f -<<EOF
apiVersion: projectcalico.org/v3
kind: CalicoNodeStatus
metadata:
  name: k01-control-plane
spec:
  classes:
    - Agent
    - BGP
    - Routes
  node: k01-control-plane
  updatePeriodSeconds: 10
EOF


 kubectl get caliconodestatus k01-control-plane -o yaml