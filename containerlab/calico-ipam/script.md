Welcome everyone to this lesson on Calico IP address management, also known as IPAM. Now, before we spin up the lab and look at how Calico IPAM works, let's look at why IPAM is required in a Kubernetes cluster. 

Now, pods (which are the atomic units for workloads in Kubernetes) are just like any other workload you would encounter (be they servers, virtual machines, or even your laptop). They need an IP address to communicate with other workloads in the network. Typically, there is a DHCP server in your network that assigns IP addresses for other types of workloads. However, in the case of Kubernetes pod, we require what is known as an IPAM plug-in to not just assign IP addresses but also manage the IP address space but also managed the IP address space or block assigned to the cluster to ensure fast pod startup. And we will look at how Calico does this in the lab. 

OK, so IPAM is required for dynamic pod creation. In Kubernetes pods are ephemeral, they are frequently created and destroyed, and as they are created, IP addresses have to be assigned to those pods. And as they are destroyed, those IPs have to be reassigned to the pool so that new pods can utilize the IP. 

The IPAM plug-in is also responsible for avoiding IP conflicts. A given IP can only be allocated to a single pod. 

Next efficient address allocation, IP addresses have to be allocated in a manner that is scalable and that ensures seamless communication between pods in the cluster. We look at this in a little bit more detail during the lab. 

And finally, IP addresses should be allocated in a manner that facilitates cross-node communication. In the pod routing section, we will look at how pods in different nodes communicate and how the assignment of IP blocks to a node facilitates that. 