don't retry same replica twice in a round
# Issue

### 1. Minimal reproduce step

In the following case, suppose the region leader is in `store1`.

```go
	ca = replicaSelectorAccessPathCase{
		reqType:   tikvrpc.CmdGet,
		readType:  kv.ReplicaReadMixed,
		staleRead: true,
		timeout:   0,
		label:     &metapb.StoreLabel{Key: "id", Value: "3"},
		accessErr: []RegionErrorType{ServerIsBusyErr, ServerIsBusyErr},
```

### 2. What did you expect to see?

```go
			accessPath: []string{
				"{addr: store3, replica-read: false, stale-read: true}",
				"{addr: store1, replica-read: false, stale-read: false}",
				"{addr: store2, replica-read: true, stale-read: false}"},
```


### 3. What did you see instead?

```go
			accessPath: []string{
				"{addr: store3, replica-read: false, stale-read: true}",
				"{addr: store1, replica-read: false, stale-read: false}",
				"{addr: store3, replica-read: true, stale-read: false}"},
```

Currently, the replica selector logic is:

1. try store3 by stale-read, since store3 has match label, but got ServerIsBusyErr.
2. retry leader in store1, but got `ServerIsBusyErr` too.
3. retry store3.

The problem is, store3 has been tried, and got ServerIsBusyErr, retry it may also got `ServerIsBusyErr`. we should try store2 by replica-read since store2 has never been tried.

### Additional contract requirements

- The "don't retry the same replica twice in a round" rule has exactly one exception: for a stale read, a replica that returned a `DataIsNotReady` region error may be retried once more by replica-read in the same round, even though it was already tried. A replica that returned any other region error (for example `ServerIsBusy`) must not be retried in the same round.
