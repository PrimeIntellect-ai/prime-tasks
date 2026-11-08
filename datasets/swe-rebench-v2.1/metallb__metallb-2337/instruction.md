Not announce Service if Endpoint is not available, but service marked to publishNotReadyAddresses
### MetalLB Version

0.14.3

### Deployment method

Charts

### Main CNI

cilium

### Kubernetes Version

1.28.5

### Cluster Distribution

cluster-api

### Describe the bug

l2 don't announce IPs for Services with publishNotReadyAddresses:true, if pod isn't running fully.

With 0.13.12, it did work and with 0.14.3, it don't work.

### To Reproduce

1. Create a Service with publishNotReadyAddresses: true
2. Start Pod which is not ready until IP is announced and used.


### Expected Behavior

IP get's announced.

### Additional Context

```
{"caller":"layer2_controller.go:82","event":"shouldannounce","ips":["ip"],"level":"debug","message":"failed no active endpoints","pool":"default","protocol":"l2","service":"namespace/name","ts":"2024-03-26T10:51:13Z"}
```

### I've read and agree with the following

- [X] I've checked all open and closed issues and my request is not there.
- [X] I've checked all open and closed pull requests and my request is not there.

### I've read and agree with the following

- [X] I've checked all open and closed issues and my issue is not there.
- [X] This bug is reproducible when deploying MetalLB from the main branch
- [X] I have read the [troubleshooting guide](https://metallb.universe.tf/troubleshooting/) and I am still not able to make it work
- [X] I checked the logs and MetalLB is not discarding the configuration as not valid
- [X] I enabled the debug logs, collected the information required from the cluster using the [collect script](https://raw.githubusercontent.com/metallb/metallb/main/troubleshooting/collect.sh) and will attach them to the issue
- [X] I will provide the definition of my service and the related endpoint slices and attach them to this issue
