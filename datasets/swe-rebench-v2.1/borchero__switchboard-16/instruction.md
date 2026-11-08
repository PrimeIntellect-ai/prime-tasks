Allow CNAME records for external-dns integration
Hi again,

Many cloud providers provide their `LoadBalancer` resources with hostname only, and no IP addresses. The hostname is usually meant to be added as a CNAME record to DNS.

Example kubernetes service status:
```
status:
  loadBalancer:
    ingress:
    - hostname: example.lb.identifier.amazonaws.com
```

It would be useful if Switchboard would also be able to pick up a `hostname` variable in the absence of an IP address, from the defined traefik service object, and create the `DNSEndpoint` resource with `recordType: CNAME` in this case. I think external-dns does something like that from `ingress` sources.

### Additional contract requirements

- The `Target` interface in package `github.com/borchero/switchboard/internal/switchboard` exposes a method `Targets(ctx context.Context, client client.Client) ([]string, error)` that returns the IPv4/IPv6 addresses or hostnames to be used as DNS targets, or an error if they cannot be retrieved.
- DNS targets are published grouped by record type: IPv4 addresses as `A` records, IPv6 addresses as `AAAA` records, and hostnames as `CNAME` records. When no hosts or no targets are provided, no DNS endpoints are produced.
