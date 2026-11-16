Per-port configs via annotations
The [annotations](https://github.com/linode/linode-cloud-controller-manager#annotations) are very useful to configure NodeBalancer options, thank you. It appears the only _port-specific_ options are for protocol and TLS cert, and the rest apply globally to the balancer on every port configuration.

It would be helpful to define options on a per-port basis, the way they're arranged in the Cloud Manager. For example, different services have different compatibility with `proxy-protocol`, and might have different health check requirements. I'm using Traefik for ingress, and as more non-HTTP services are added as entrypoints, ports are added to the same `LoadBalancer` resource yet it becomes unreasonable to apply the same NB config to all equally.

One route might be to allow the `linode-loadbalancer-port-*` JSON entries to contain other annotation key/value pairs, which merge into and override the global values before being passed to the underlying NodeBalancer API for that port-config.  Does that make sense?

Thanks!

### Additional contract requirements

- The default Proxy Protocol setting is configured with the annotation `service.beta.kubernetes.io/linode-loadbalancer-default-proxy-protocol`, whose value is one of `none`, `v1`, or `v2`.
- A port-specific configuration is provided with the annotation `service.beta.kubernetes.io/linode-loadbalancer-port-<port>`; its JSON value supports the key `proxy-protocol` (one of `none`, `v1`, or `v2`), which overrides the default for that port.
- If the default Proxy Protocol annotation is set to a value other than `none`, `v1`, or `v2`, the controller must return an error.
