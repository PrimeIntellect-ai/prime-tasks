Should remove LB backend pool reference from VMSS with 0 capacity when updating backend pool type to nodeIP
<!-- Please use this template while reporting a bug and provide as much info as possible. Not doing so may result in your bug not being addressed in a timely manner. Thanks!

If the matter is security related, please disclose it privately via https://kubernetes.io/security/
-->


#### What happened:

We only decouple VMSS with non-zero capacity from the LB when updating from NIC to IP-based Load Balancer.

#### What you expected to happen:

VMSS with zero capacity should also be decoupled from the LB.

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
