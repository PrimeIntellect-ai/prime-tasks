Add a Resolver interface
Right now ureq will always use to_socket_addrs to lookup hostnames. For testing, it would be useful to force all lookups to resolve to localhost and a test server running there. This is particularly useful when a variety of hostnames are needed, or when testing large transfers that would be expensive to send over a real network.

We should add an internal Resolver interface that uses to_socket_addrs by default, but can be overridden during testing to provide mocked-out results.

### Additional contract requirements

- Add a public trait `Resolver` at the crate root, usable as `ureq::Resolver`, with the method `fn resolve(&self, netloc: &str) -> std::io::Result<Vec<std::net::SocketAddr>>`. Implementors of the trait must be `Send + Sync`.
- Add a public method `Agent::set_resolver(&mut self, resolver: impl Resolver + 'static) -> &mut Self`. It replaces the agent's resolver and returns a mutable reference to the same agent so calls can be chained. The supplied resolver must be `Send + Sync + 'static`.
- A closure of type `Fn(&str) -> std::io::Result<Vec<std::net::SocketAddr>>` is a valid resolver.
- The `netloc` argument passed to `resolve` is the host name being looked up, optionally including its port.
