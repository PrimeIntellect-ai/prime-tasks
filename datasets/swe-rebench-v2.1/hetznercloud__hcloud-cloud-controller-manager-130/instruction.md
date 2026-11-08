Changing the value of the `load-balancer.hetzner.cloud/disable-public-network` annotation for an existing service has no effect
This was originally reported in issue #120. It seems like sending the update to our backend is missing.

### Additional contract requirements

For an existing service with an associated load balancer, reconciliation must honor the current value of the `load-balancer.hetzner.cloud/disable-public-network` annotation. A value of `true` means the load balancer's public network interface must be disabled; a value of `false` means it must be enabled. When the current interface state differs from that setting, reconciliation must update it.
