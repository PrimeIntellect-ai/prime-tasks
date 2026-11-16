Support DNS discovery of DNS names on routes
## Feature Request
Support resolving DNS names for routes and using resolved ips, excluding self ip.

#### Use Case:
Boostraping a NATS cluster using Consul

#### Proposed Change:
Resolve DNS names instead of directly calling net.DialTCP() for routes

#### Who Benefits From The Change(s)?
Environments that use DNS as service discovery, including Consul clusters.

### Additional contract requirements

- Add a method on the server type with the signature
  `getRandomIP(resolver netResolver, url string, excludedAddresses map[string]struct{}) (string, error)`.
  Given a `host:port` address it resolves the host through the supplied resolver, removes every
  resolved `ip:port` address that is present in `excludedAddresses`, and returns one of the remaining
  addresses (chosen at random) with the original port. If the host is already an IP address it is
  returned unchanged. If the resolver returns no addresses, the original address is returned
  unchanged. It returns a non-nil error when the address has no port, when the host lookup fails, and
  when every resolved address is excluded.
- Add a resolver abstraction `netResolver` with the method
  `LookupHost(ctx context.Context, host string) ([]string, error)`.
- Add a `resolver` field of type `netResolver` to the cluster options struct (`ClusterOpts`) so that a
  custom resolver can be supplied for route connections.


- When a route hostname resolves only to this server's own address, do not emit a debug log containing `Detected route to self`.
