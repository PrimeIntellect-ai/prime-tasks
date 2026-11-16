replica selector v2 not compatible with v1 in mixed mode
# Issue

### 1. Minimal reproduce step

This issue was found in #1267

```go
	s.changeRegionLeader(3)
	ca = replicaSelectorAccessPathCase{
		reqType:   tikvrpc.CmdGet,
		readType:  kv.ReplicaReadMixed,
		staleRead: false,
		accessErr: []RegionErrorType{ServerIsBusyErr, ServerIsBusyErr, ServerIsBusyErr},
```

### 2. What did you expect to see?

```go
		expect: &accessPathResult{
			accessPath: []string{
				"{addr: store1, replica-read: true, stale-read: false}",
				"{addr: store2, replica-read: true, stale-read: false}",
				"{addr: store3, replica-read: true, stale-read: false}",
			},
```


### 3. What did you see instead?

```go
		expect: &accessPathResult{
			accessPath: []string{
				"{addr: store1, replica-read: true, stale-read: false}",
				"{addr: store3, replica-read: true, stale-read: false}",
				"{addr: store2, replica-read: true, stale-read: false}",
			},
```
