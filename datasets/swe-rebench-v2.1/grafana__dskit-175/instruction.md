When lifecycler reuses existing LEAVING entry, it waits for another heartbeat period to write ACTIVE state to ring
When lifecycler finds existing entry in the ring, it will reuse state and tokens from it. If the state was LEAVING and entry has enough tokens, lifecycler immediately switches its internal state to ACTIVE, but it doesn't update the ring with this state, and instead waits for next heartbeat.

With long heartbeats (eg. 2 minutes), this makes the time until ACTIVE state of lifecycler is visible to other components longer.

This also affects how soon lifecycler reports "ready" in its `CheckReady` [function](https://github.com/grafana/dskit/blob/789ec0ca4a3b372335fad1c73147366a23ddc8b6/ring/lifecycler.go#L192), because it actually checks the state in the ring. (This is correct behaviour, if it only consulted its internal state, we could report "ready" before other components saw it as active, which could result in an outage in case of Mimir ingesters for example).

### Additional contract requirements

- When reusing an existing ring entry, the published entry must reflect the lifecycler's configured address and zone; in the long-heartbeat test these are `1.1.1.1:111` and `new`.
