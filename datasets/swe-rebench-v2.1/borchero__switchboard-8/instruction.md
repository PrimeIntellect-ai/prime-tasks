Support dual-stack/multiple target IPs
[Only the first IP of a target is used for ExternalDNS records](https://github.com/borchero/switchboard/blob/f9ee58652cb4a22dc44ca3d0f370f92deda57770/internal/switchboard/targets.go#L33-L37). To support dual-stack services, records for all IPs of the target should be created.

(Depends on #5)

### Additional contract requirements

- Add a public method `IPs(ctx context.Context, client client.Client) ([]string, error)` on the `Target` type in package `github.com/borchero/switchboard/internal/switchboard`. It returns the IP addresses that should be used as DNS targets for the target Service: all LoadBalancer ingress IPs if any are present, otherwise the Service's cluster IPs. It returns an error if the Service cannot be retrieved.
- When the external-dns integration creates DNS records for a target Service, it creates, for every host, one record per IP address family present among the target IPs: an `A` record carrying all IPv4 target addresses and an `AAAA` record carrying all IPv6 target addresses.
