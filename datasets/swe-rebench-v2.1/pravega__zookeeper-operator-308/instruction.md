Custom annotations for services created by operator, optional LoadBalancer
### Description

It would be great to have ability to attach custom annotations for services created by the Operator, and to make attaching LoadBalancer for AdminServer service optional

### Importance

This is especially important  for admin-server service, since by default LoadBalancer with default configuration is being attached. For my environment it conflicts with automated provisioning of resources which requires to have specific annotation on resources created by 3rd-party tools. So it's kind of blocker for me.
Additionally, I believe it would be great to make attaching LoadBalancer optional since LB costs money (at least in AWS EKS) and some people do not really use it outside of k8s.

### Location

pkg/apis/zookeeper/v1beta1/zookeepercluster_types.go
pkg/zk/generators.go

### Suggestions for an improvement

I'm going to create PR if nobody minds

### Additional contract requirements

- Users can configure custom annotations for the operator-created client, headless, and AdminServer Services through `spec.clientService.annotations`, `spec.headlessService.annotations`, and `spec.adminServerService.annotations`, respectively. Apply the configured annotations to the corresponding Service.
- Users can control whether the AdminServer Service uses a LoadBalancer through `spec.adminServerService.external`: when `true`, the Service uses a LoadBalancer; when `false`, it does not.
