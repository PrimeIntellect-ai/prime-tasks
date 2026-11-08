Create session blocked until connection to every peer is established
### What version of Cassandra are you using?
Yugabyte 2.0.1

### What version of Gocql are you using?
master (07ace3bab0f84bb88477bab5d79ba1f7e1da0169)

### What did you do?
When creating a session without `DisableInitialHostLookup` then the session will not be blocked from being created if ANY of the peers are down until the reconnect policy fails. Instead, there should be an option to do the initial host lookup but only connect to other hosts asynchronously.

### What did you expect to see?
I expected the session to be created and asynchronously connect to other peers.

### What did you see instead?
Instead CreateSession is blocked until a connection to all peers is established.

---
Logs with `gocql_debug`:
2019/10/22 16:03:25 gocql: Session.handleNodeUp: 10.142.0.175:9042
2019/10/22 16:03:31 connection failed "10.142.0.174": gocql: no response to connection startup within timeout, reconnecting with *gocql.ConstantReconnectionPolicy

The downside of setting `DisableInitialHostLookup` is that it won't discover any peers until a topology event. I'd like to try to connect to the peers discovered originally but not make them block. At the risk of making yet another flag, I'd like to propose adding `DisableInitialSyncPeerConnect`. If that is set to true, then after getting the peers they're connected to asynchronously and Session.init would return once one is connected. Alternatively we could call the option `RequireSinglePeer` or something.

### Additional contract requirements

- Add a public interface `ReadyPolicy` in `policies.go` with a single method `Ready() bool`.
- Add a public function `SingleHostReadyPolicy(p HostSelectionPolicy)` in `policies.go`. It wraps the given host-selection policy and returns a policy that implements both `HostSelectionPolicy` and `ReadyPolicy`. Its `HostUp(host *HostInfo)` method forwards the host-up event to the wrapped policy and records that the policy is ready; its `Ready() bool` method reports whether a host has been marked up.
- When a session is created with a host-selection policy that implements `ReadyPolicy`, session creation returns as soon as that policy reports ready (for example after a single host is connected), while connections to the remaining discovered peers are established asynchronously in the background.
