UDP services may trigger unnecessary LoadBalancer updates
<!-- Please use this template while reporting a bug and provide as much info as possible. Not doing so may result in your bug not being addressed in a timely manner. Thanks!

If the matter is security related, please disclose it privately via https://kubernetes.io/security/
-->


#### What happened:

While nothing changed to all LoadBalancer service specs, scaling node number or restart controller manager would trigger LoadBalancer update APIs. This is because `EnableTCPReset` value is different between expected LB rule and existing LB rule when the protocol is not TCP, and hence `equalLoadBalancingRulePropertiesFormat()` would treat the LB rule as updated.

And here are the related logs:

```
I0129 07:27:01.471484       1 azure_loadbalancer.go:1516] reconcileLoadBalancer for service(default/test): lb(test-rg/kubernetes) wantLb(true) resolved load balancer name
I0129 07:27:01.530862       1 azure_loadbalancer.go:2106] getExpectedLBRules lb name (kubernetes) rule name (a30cf55982b684c1993a23dd1e177c98-UDP-24899)
I0129 07:27:01.530954       1 azure_loadbalancer.go:1696] reconcileLoadBalancer for service (default/test)(true): lb rule(a30cf55982b684c1993a23dd1e177c98-UDP-24899) - dropping
```

#### What you expected to happen:

* `EnableTCPReset` should only be set in LB rule when the protocol is TCP.
[HIDDEN]

#### How to reproduce it (as minimally and precisely as possible):

Create a UDP LoadBalancer service in the cluster and then restart controller manager. After a while, there would be new write operations in LoadBalancer activities （this could be observed on the Azure portal）.

#### Anything else we need to know?:

#### Environment:

- Kubernetes version (use `kubectl version`):
- Cloud provider or hardware configuration:
- OS (e.g: `cat /etc/os-release`):
- Kernel (e.g. `uname -a`):
- Install tools:
- Network plugin and version (if this is a network-related bug):
- Others:

### Additional contract requirements

- Rule equality must ignore differences in `EnableTCPReset` for non-TCP protocols and must consider `EnableTCPReset` when the protocol is TCP.
