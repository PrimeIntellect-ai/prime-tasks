Don't invalid region in tryFollowers when set user-defined req timeout and meet DeadLineExceededErr
# Issue

### 1. Minimal reproduce step

In the following case, suppose the region leader is in `store1`.

```go
	ca = replicaSelectorAccessPathCase{
		reqType:   tikvrpc.CmdGet,
		readType:  kv.ReplicaReadMixed,
		staleRead: true,
		timeout:   time.Second,
		label:     nil,
		accessErr: []RegionErrorType{DeadLineExceededErr, ServerIsBusyErr, ServerIsBusyErr},
```

### 2. What did you expect to see?

No backoff.

```go
		expect: &accessPathResult{
			accessPath: []string{
				"{addr: store1, replica-read: false, stale-read: true}",
				"{addr: store2, replica-read: true, stale-read: false}",
				"{addr: store3, replica-read: true, stale-read: false}"},
			regionIsValid:   true,
		},
```


### 3. What did you see instead?

```go
		expect: &accessPathResult{
			...
			regionIsValid:   false,
		},
```

The request has user-defined timeout 1s, the replica selector logic is:

1. try store1 by stale-read, but got DeadLineExceededErr.
2. retry store2, got `ServerIsBusyErr`.
3. retry store3, got `ServerIsBusyErr` too, and then invalidate the region in cache.

The expected result is doesn't invalidate region in cache, and the do fast retry without user-defined timeout.

### Additional contract requirements

- For the described configured-timeout case, after the leader attempt reports a deadline exceeded error and follower attempts fail with server-is-busy errors, do not invalidate the cached region. The retry must be fast and must not wait out the user-defined timeout.
- “No backoff” in this scenario means no region-scheduling or region-invalidation backoff; ordinary error-specific retry handling is not prohibited.
