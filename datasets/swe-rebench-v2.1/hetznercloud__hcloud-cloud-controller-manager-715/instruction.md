LoadBalancer does not populate IP field when `disable-public-network` is set.
I have created a service of type `LoadBalancer`, with the annotation `load-balancer.hetzner.cloud/disable-public-network: "true"`. The load-balancer has a private IP address assigned on my cluster's network (`172.29.0.3`), and responds correctly on this address. But, the status does not contain the LB's IP address:

```yaml
  status:
    loadBalancer: {}
```

When I create a service without the annotation, the status is correctly updated:

```yaml
  status:
    loadBalancer:
      ingress:
      - ip: 167.235.<snip>
      - ip: 2a01:4f8:<snip>
```

I think even if public access is disabled, the external IP should still be populated with the service's private network address, so that servers on my HCloud network (but outside the k8s cluster) can extract the address they can reach the service on. Also, without the load-balancer IP address, `external-dns` fails to add a record for this load-balancer.

### Additional contract requirements

The `LoadBalancer` status ingress list is populated as follows, for both `GetLoadBalancer` and `EnsureLoadBalancer`:

- When public networking is enabled (the default), the status contains the load balancer's public IPv4 address and, unless IPv6 is disabled, its public IPv6 address.
- The load balancer's private network address(es) are appended to the status ingress list, unless the `load-balancer.hetzner.cloud/disable-private-ingress` annotation is set to `"true"` (or the controller is configured to disable private ingress by default).
- When public networking is disabled (`load-balancer.hetzner.cloud/disable-public-network: "true"`), the public addresses are omitted, but the private network address(es) are still populated as described above.
