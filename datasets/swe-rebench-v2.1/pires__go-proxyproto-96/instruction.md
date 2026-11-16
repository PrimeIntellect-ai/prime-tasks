CIDR based policy for a simple non-PROXY traffic
I believe I'm not the first one who tries to solve the PROXY PROTOCOL vs no PROXY PROTOCOL traffic problem for a single listener. This is a very common behavior for k8s clusters that use PROXY_PROTOCOL based loadbalancers.

In short, the k8s pods clients local traffic doesn't use PROXY PROTOCOL, therefore accessing the service locally that expects PROXY PROTOCOL fails. There are two dirty solutions for this: route local traffic to the external loadbalancer IP (to add the required header), or fallback due to timeout.

Both options above have flaws: LB adds latency and load, timeout adds latency and acts unpredictably on heavy load.

I know that it's possible to create an extra wrapper around the original Conn, but this would look dirty. I propose to add a new SKIP policy, which will treat a connection as a regular one and it won't trigger proxyproto handlers. The SKIP policy can be defined in a `PolicyFunc` callback.

Objections?

### Additional contract requirements

- The package `proxyproto` exposes a policy value named `SKIP`. When a connection's policy resolves to `SKIP`, the accepted connection is handled as an ordinary connection and PROXY-protocol handling is not triggered.
- The package `proxyproto` exposes a function `SkipProxyHeaderForCIDR(skipHeaderCIDR *net.IPNet, def Policy) PolicyFunc`. The returned `PolicyFunc` returns `SKIP` when the upstream address is contained in `skipHeaderCIDR`, and returns `def` otherwise. When `skipHeaderCIDR` is nil, no address is skipped and `def` is returned. When the upstream address cannot be parsed, the returned error is propagated.
