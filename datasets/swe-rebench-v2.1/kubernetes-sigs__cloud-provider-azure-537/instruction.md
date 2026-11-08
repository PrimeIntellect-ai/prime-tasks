If nodes are are not in a ready state when the controller manager boots, the cache is stale causing 15 min delay of LB deployment
<!-- Please use this template while reporting a bug and provide as much info as possible. Not doing so may result in your bug not being addressed in a timely manner. Thanks!
-->


**What happened**:
When adding functionality to the e2e tests in https://github.com/kubernetes-sigs/cluster-api-provider-azure/issues/857 for CAPZ, I found the e2e tests would fail if run against a single control plane node cluster.  This would occasionally happen when running multi-node control plane clusters as well.  This was initially reported with some of the message in #338

What happens is the control manager comes [online and queries for azure machines power status.](https://github.com/kubernetes/kubernetes/blob/ec560b9737537be8c688776461bc700e8ddedb9d/staging/src/k8s.io/legacy-cloud-providers/azure/azure_vmss.go#L211)  Since the machines are not available yet [they are not in the cache.](https://github.com/kubernetes/kubernetes/blob/ec560b9737537be8c688776461bc700e8ddedb9d/staging/src/k8s.io/legacy-cloud-providers/azure/azure_vmss_cache.go#L307) When the request comes in for the [load balancer the cache is queried](https://github.com/kubernetes/kubernetes/blob/ec560b9737537be8c688776461bc700e8ddedb9d/staging/src/k8s.io/legacy-cloud-providers/azure/azure_vmss.go#L1196) and reports that the node [does not exist as a VMAS and attempts to run the VMSS code](https://github.com/kubernetes/kubernetes/blob/ec560b9737537be8c688776461bc700e8ddedb9d/staging/src/k8s.io/legacy-cloud-providers/azure/azure_vmss.go#L1217) hence the following error message.  When it is found the in the cache it goes down the [correct code path](https://github.com/kubernetes/kubernetes/blob/master/staging/src/k8s.io/legacy-cloud-providers/azure/azure_vmss.go#L1272).

```
E0802 23:30:06.928574       1 azure_vmss.go:1116] EnsureHostInPool(default/ingress-nginx-ilb): backendPoolID(/subscriptions/b9d9436a-0c07-4fe8-b779-2c1030bd7997/resourceGroups/capz-e2e-72fll1/providers/Microsoft.Network/loadBalancers/capz-e2e-72fll1-internal/backendAddressPools/capz-e2e-72fll1) - failed to ensure host in pool: "not a vmss instance"
```



I was able to confirm the cache was missing the node by adding some custom logs to the controller-manager. The initial [request to the cache](https://github.com/kubernetes/kubernetes/blob/master/staging/src/k8s.io/legacy-cloud-providers/azure/azure_vmss_cache.go#L277) doesn't have the nodes:

```
I0802 23:27:42.217347       1 azure_vmss.go:309] Can not extract scale set name from providerID (azure:///subscriptions/b9d9436a-0c07-4fe8-b779-2c1030bd7997/resourceGroups/capz-e2e-72fll1/providers/Microsoft.Compute/virtualMachines/capz-e2e-72fll1-control-plane-wjqp5), assuming it is mananaged by availability set: not a vmss instance
I0802 23:27:42.217487       1 azure_vmss.go:192] JJS: powerstatus node capz-e2e-72fll1-control-plane-wjqp5
I0802 23:27:42.217638       1 azure_vmss_cache.go:238] JJS: enter cache calls for nodes
I0802 23:27:42.217725       1 azure_vmss_cache.go:240] JJS: listing nodes for rg: capz-e2e-72fll1
I0802 23:27:42.651485       1 azure_backoff.go:100] VirtualMachinesClient.List(capz-e2e-72fll1) success
I0802 23:27:42.651641       1 azure_vmss_cache.go:246] JJS: nodes found: %!s(int=1)
I0802 23:27:42.651750       1 azure_vmss_cache.go:249] JJS: adding node to local cache {{%!s(*http.Response=<nil>)} %!s(*compute.Plan=<nil>) %!s(*compute.VirtualMachineProperties=&{0xc001fd3eb0 0xc002022960 <nil> 0xc001f13ea0 0xc0020280a0 <nil> <nil> <nil> <nil>   <nil> <nil> 0xc001fd3fd0 <nil> <nil> 0xc001fd3ea0}) %!s(*[]compute.VirtualMachineExtension=<nil>) %!s(*compute.VirtualMachineIdentity=<nil>) %!s(*[]string=&[1]) %!s(*string=0xc001fd2a60) %!s(*string=0xc001fd2a50) %!s(*string=0xc001fd2a70) %!s(*string=0xc001fd2a80) map[Name:%!s(*string=0xc001fd2a90) creationTimestamp:%!s(*string=0xc001fd2ab0) jobName:%!s(*string=0xc001fd2ad0) kubernetes.io_cluster_capz-e2e-72fll1-control-plane-wjqp5:%!s(*string=0xc001fd2af0) sigs.k8s.io_cluster-api-provider-azure_cluster_capz-e2e-72fll1:%!s(*string=0xc001fd2b10) sigs.k8s.io_cluster-api-provider-azure_role:%!s(*string=0xc001fd2b30)]}
I0802 23:27:42.651962       1 azure_vmss_cache.go:278] JJS: VMAS Nodes: map[capz-e2e-72fll1-control-plane-wjqp5:{}]
I0802 23:27:42.652194       1 azure_vmss_cache.go:280] JJS: asking for node capz-e2e-72fll1-control-plane-wjqp5
I0802 23:27:42.698224       1 azure_instances.go:232] InstanceShutdownByProviderID gets power status "running" for node "capz-e2e-72fll1-control-plane-wjqp5"
```

You can see request for powerstatus here:

```
I0802 23:28:32.709471       1 azure_vmss.go:192] JJS: powerstatus node capz-e2e-72fll1-md-0-q2st9
I0802 23:28:32.709626       1 azure_vmss_cache.go:278] JJS: VMAS Nodes: map[capz-e2e-72fll1-control-plane-wjqp5:{}]
I0802 23:28:32.709652       1 azure_vmss_cache.go:280] JJS: asking for node capz-e2e-72fll1-md-0-q2st9
I0802 23:28:32.709836       1 azure_vmss.go:309] Can not extract scale set name from providerID (azure:///subscriptions/b9d9436a-0c07-4fe8-b779-2c1030bd7997/resourceGroups/capz-e2e-72fll1/providers/Microsoft.Compute/virtualMachines/capz-e2e-72fll1-md-0-q2st9), assuming it is mananaged by availability set: not a vmss instance
```

And request for [EnsureHostsInPool](https://github.com/kubernetes/kubernetes/blob/master/staging/src/k8s.io/legacy-cloud-providers/azure/azure_vmss.go#L1178) doesn't have the VMAS nodes in the cache:

```
I0802 23:30:06.928474       1 azure_vmss.go:1077] JJS: EnsureHostsInPool node capz-e2e-72fll1-md-0-q2st9
I0802 23:30:06.928488       1 azure_vmss_cache.go:278] JJS: VMAS Nodes: map[capz-e2e-72fll1-control-plane-wjqp5:{}]
I0802 23:30:06.928518       1 azure_vmss_cache.go:280] JJS: asking for node capz-e2e-72fll1-md-0-q2st9
I0802 23:30:06.928529       1 azure_vmss.go:1097] JJS: EnsureHostsInPool node false managedby VMAS
I0802 23:30:06.928542       1 azure_vmss.go:1113] JJS: EnsureHostsInPool entered EnsureHostInPool started%!(EXTRA bool=false)
I0802 23:30:06.928549       1 azure_vmss.go:832] ensuring node "capz-e2e-72fll1-md-0-q2st9" of scaleset "" in LB backendpool "/subscriptions/b9d9436a-0c07-4fe8-b779-2c1030bd7997/resourceGroups/capz-e2e-72fll1/providers/Microsoft.Network/loadBalancers/capz-e2e-72fll1-internal/backendAddressPools/capz-e2e-72fll1"
E0802 23:30:06.928574       1 azure_vmss.go:1116] EnsureHostInPool(default/ingress-nginx-ilb): backendPoolID(/subscriptions/b9d9436a-0c07-4fe8-b779-2c1030bd7997/resourceGroups/capz-e2e-72fll1/providers/Microsoft.Network/loadBalancers/capz-e2e-72fll1-internal/backendAddressPools/capz-e2e-72fll1) - failed to ensure host in pool: "not a vmss instance"
```

**What you expected to happen**:

**How to reproduce it**:
Follow the instructions at https://github.com/kubernetes-sigs/cluster-api-provider-azure/issues/857  or create a single node control plane cluster then after the control node is up, add a worker node.

**Anything else we need to know?**:
In multi control plane node clusters, leader election occurs in the controller-manager and causes the cache to reload.  This is why it only happens occasionally in that scenario.

I believe this could happen if a node is added at a later time and was expected to be in the backend pool but wasn't and so could be important to fix.


**Environment**:
- Kubernetes version (use `kubectl version`): `1.18.6`
- OS (e.g. from /etc/os-release):
- Kernel (e.g. `uname -a`):
- Install tools: CAPZ
- Others:

### Additional contract requirements

When a node becomes available after availability-set cache data has been populated, load-balancer backend handling must recognize the node using current availability-set information so stale cache contents do not delay deployment or treat the node as a VMSS instance.
