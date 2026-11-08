PublicIPReferencedByMultipleIPConfigs when reusing the same IP via pip-name annotation
<!-- Please use this template while reporting a bug and provide as much info as possible. Not doing so may result in your bug not being addressed in a timely manner. Thanks!

If the matter is security related, please disclose it privately via https://kubernetes.io/security/
-->


#### What happened:

PublicIPReferencedByMultipleIPConfigs failures would happen when reusing the same IP via service annotations.

Sample error message:

```
{
    "code": "PublicIPReferencedByMultipleIPConfigs",
    "message": "Public ip address /subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/publicIPAddresses/pip is referenced by multiple ipconfigs in resource /subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/loadBalancers/kubernetes."
}
```

#### What you expected to happen:

The new service with pip-name annotation should succeed and reuse the public IP address when ports are not conflicted with existing rules.

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
