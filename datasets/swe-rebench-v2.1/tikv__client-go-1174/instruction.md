stale read request shoudn't retry leader if leader is already tried
# Issue1

### 1. Minimal reproduce step

In the following case, suppose the region leader is in `store1`.

```go
	ca = replicaSelectorAccessPathCase{
		reqType:   tikvrpc.CmdGet,
		readType:  kv.ReplicaReadMixed,
		staleRead: true,
		accessErr: []RegionErrorType{DataIsNotReadyErr, ServerIsBusyErr},
	}
```

### 2. What did you expect to see?

```go
	accessPath: []string{
		"{addr: store1, replica-read: false, stale-read: true}",
		"{addr: store2, replica-read: true, stale-read: false}",
		"{addr: store3, replica-read: true, stale-read: false}", }
```

### 3. What did you see instead?

```go
	accessPath: []string{
		"{addr: store1, replica-read: false, stale-read: true}",
		"{addr: store1, replica-read: false, stale-read: false}", // retry store1 by leader read.
		"{addr: store2, replica-read: true, stale-read: false}",}
```

After https://github.com/tikv/tikv/pull/15726 fixed, normally, the leader won't return `DataIsNotReadyErr`, so no need to retry the leader by leader-read again if the leader is already tried.


# Issue2

other related test case is the following.

### 1. Minimal reproduce step

In the following case, suppose the region leader is in `store1`.

```go
	ca = replicaSelectorAccessPathCase{
		reqType:   tikvrpc.CmdGet,
		readType:  kv.ReplicaReadMixed,
		staleRead: true,
		label:     &metapb.StoreLabel{Key: "id", Value: "2"},
		accessErr: []RegionErrorType{DataIsNotReadyErr, ServerIsBusyErr},
```

### 2. What did you expect to see?

```go
	accessPath: []string{
		"{addr: store2, replica-read: false, stale-read: true}",
		"{addr: store1, replica-read: false, stale-read: false}",
		"{addr: store2, replica-read: true, stale-read: false}"},
```

### 3. What did you see instead?

```go
	accessPath: []string{
		"{addr: store2, replica-read: false, stale-read: true}",
		"{addr: store1, replica-read: false, stale-read: false}", // retry leader.
		"{addr: store1, replica-read: false, stale-read: false}"}, // retry leader again? the leader is ServerIsBusyErr, should try follower in store2?
```

### Additional contract requirements

- The `internal/locate` package must declare a package-level variable `randIntn` of type `func(int) int`, and replica selection must obtain its random choices through it.
- The `internal/locate` package must provide a method `resetSlowScore()` on `*SlowScoreStat` that resets the slow-score statistic to zero.
