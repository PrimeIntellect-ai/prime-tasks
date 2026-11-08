Disabling IPv6 for loadbalancers
Hello,
Is there an option "annotation/flag" to disable IPv6 Support ?

I have upgraded CCM to v1.9.1 but the external-dns erroring to : the target A is not a valid record. As there is an open issue with external-dns regarding IPv6 support  kubernetes-sigs/external-dns/issues/2044

I understand the feature was re-enabled #137 , but the ingress-nginx-controller is always publishing both IPv4 and IPv6 even with ConfigMap -> disable-ipv6-dns: "true"

The only workaround I found is to go back to v1.8.1 where IPv6 is completely not supported.

### Additional contract requirements

- IPv6 can be disabled per load balancer by setting the Service annotation `load-balancer.hetzner.cloud/ipv6-disabled` to `true`. When this annotation is `true`, the load balancer's public IPv6 ingress address is omitted from the load balancer status; otherwise the public IPv6 ingress address is included alongside the public IPv4 address.
