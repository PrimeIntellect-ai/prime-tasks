RulesUseSameBackendPortProtocolAndPoolAndFrontendIPWithFloatingIPEnabled error when using multiple ports with HA
<!-- Please use this template while reporting a bug and provide as much info as possible. Not doing so may result in your bug not being addressed in a timely manner. Thanks!
-->

**What happened**:

When using mutiple ports in service with annotation `service.beta.kubernetes.io/azure-load-balancer-enable-high-availability-ports: true`, the following error was reported:

```sh
Error syncing load balancer: failed to ensure load balancer: Retriable: false, RetryAfter: 0s, HTTPStatusCode: 400, RawError: Retriable: false, RetryAfter: 0s, HTTPStatusCode: 400, RawError: {
  "error": {
    "code": "RulesUseSameBackendPortProtocolAndPoolAndFrontendIPWithFloatingIPEnabled",
    "message": "Load balancing rules /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/loadBalancers/kubernetes-internal/loadBalancingRules/a0de5d44226a749d393350b214d2c579-TCP-80 and /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/loadBalancers/kubernetes-internal/loadBalancingRules/a0de5d44226a749d393350b214d2c579-TCP-443 with floating IP enabled use the same protocol All and backend port 0 and frontend IP /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/loadBalancers/kubernetes-internal/frontendIPConfigurations/a0de5d44226a749d393350b214d2c579, and must not be used with the same backend address pool /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/loadBalancers/kubernetes-internal/backendAddressPools/kubernetes.",
    "details": []
  }
}
```

**What you expected to happen**:

Errors shouldn't happen and the service should be created successfully.

**How to reproduce it**:

Create a service with multiple ports and enable HA ports feature.

**Anything else we need to know?**:

This is no such issue when only have one port.

**Environment**:
- Kubernetes version (use `kubectl version`): 1.20
- OS (e.g. from /etc/os-release):
- Kernel (e.g. `uname -a`):
- Install tools:
- Others:
