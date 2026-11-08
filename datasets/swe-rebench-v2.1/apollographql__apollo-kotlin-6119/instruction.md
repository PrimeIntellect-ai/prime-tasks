Using `NetworkMonitor` to monitor offline state
### Use case

We'd love to use `NetworkMonitor` to monitor network state independently of GraphQL operations. Currently we are able to check the current state of the network and wait for the online state, but we are not able to wait for the offline state.

### Describe the solution you'd like

Would it be possible to add a `Flow<Boolean>` to the API? Or a `waitForOffline` suspending function?

### Additional contract requirements

`NetworkMonitor` exposes the current network state as a `StateFlow<Boolean?>` named `isOnline`. The flow emits the current state (`true` when the device is online, `false` when it is offline) and updates as connectivity changes, so callers can observe the network going offline independently of any GraphQL operation. While the state is not yet known the flow may emit `null`.
