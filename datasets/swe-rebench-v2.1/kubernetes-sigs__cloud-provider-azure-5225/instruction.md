Should ignore the case of lb name when determing if the load balancer is an internal one
<!-- Please use this template while reporting a bug and provide as much info as possible. Not doing so may result in your bug not being addressed in a timely manner. Thanks!

If the matter is security related, please disclose it privately via https://kubernetes.io/security/
-->


#### What happened:

https://github.com/kubernetes-sigs/cloud-provider-azure/blob/7c0a8afb84df58905abe03583929f0f70ad48236/pkg/provider/azure_standard.go#L250

We should ignore the case of lb name when determing if the load balaner is an internal one.
For example: kubernetes-internal is an internal lb, KUBERNETES_INTERNAL is also an internal lb.

#### What you expected to happen:

#### How to reproduce it (as minimally and precisely as possible):

#### Anything else we need to know?:

#### Environment:

- Kubernetes version (use `kubectl version`):
- Cloud provider or hardware configuration:
- OS (e.g: `cat /etc/os-release`):
- Kernel (e.g. `uname -a`):
- Install tools:
- Network plugin and version (if this is a network-related bug):
- Others:
