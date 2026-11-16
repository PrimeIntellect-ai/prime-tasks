tryIdleReplica strategy shouldn't work for write request
# Issue

### 1. Minimal reproduce step

In the following case, suppose the region leader is in `store1`.

```go
        // Try idle replica strategy not support write request.
	ca = replicaSelectorAccessPathCase{
		reqType:         tikvrpc.CmdPrewrite,
		readType:        kv.ReplicaReadLeader,
		busyThresholdMs: 10,
		accessErr:       []RegionErrorType{ServerIsBusyWithEstimatedWaitMsErr, ServerIsBusyWithEstimatedWaitMsErr},
```

### 2. What did you expect to see?

```go
		expect: &accessPathResult{
			accessPath: []string{
				"{addr: store1, replica-read: false, stale-read: false}",
				"{addr: store1, replica-read: false, stale-read: false}",
				"{addr: store1, replica-read: false, stale-read: false}",
			},
```


### 3. What did you see instead?

```go
		expect: &accessPathResult{
			accessPath: []string{
				"{addr: store1, replica-read: false, stale-read: false}",
				"{addr: store2, replica-read: true, stale-read: false}",
				"{addr: store3, replica-read: true, stale-read: false}",
			},
```

The request has `BusyThresholdMs=10`, the replica selector logic is:

1. Try store1, which is leader. got `ServerIsBusyWithEstimatedWaitMsErr`.
2. Try store2 by replica-read, It's is invalid:
  a. leader is in store1, and this is a write request, shouldn't send to store2 which is a follower.
  b. write request shouldn't use replica-read.
3. Try store3 by replica-read, It's is invalid too.
