Nil Pointer in watchers while running in Arbitrum
```
panic: runtime error: invalid memory address or nil pointer dereference
[signal 0xc0000005 code=0x0 addr=0x58 pc=0x7ff75be2a3d5]

goroutine 32836 [running]:
github.com/livepeer/go-livepeer/eth/watchers.(*SenderWatcher).handleBlockEvents(0xc002c89fd0, {0xc000882100, 0x1c, 0x0})
        D:/a/go-livepeer/go-livepeer/eth/watchers/senderwatcher.go:152 +0x55
created by github.com/livepeer/go-livepeer/eth/watchers.(*SenderWatcher).Watch
        D:/a/go-livepeer/go-livepeer/eth/watchers/senderwatcher.go:116 +0x385
panic: runtime error: invalid memory address or nil pointer dereference
[signal 0xc0000005 code=0x0 addr=0x58 pc=0x7ff75be2c595]

goroutine 33 [running]:
github.com/livepeer/go-livepeer/eth/watchers.(*ServiceRegistryWatcher).handleBlockEvents(0xc000283f80, {0xc000882100, 0x1c, 0x0})
        D:/a/go-livepeer/go-livepeer/eth/watchers/serviceRegistryWatcher.go:61 +0x55
github.com/livepeer/go-livepeer/eth/watchers.(*ServiceRegistryWatcher).Watch(0xc000211e80)
        D:/a/go-livepeer/go-livepeer/eth/watchers/serviceRegistryWatcher.go:49 +0x20a
created by main.main
        D:/a/go-livepeer/go-livepeer/cmd/livepeer/livepeer.go:587 +0x43f8
panic: runtime error: invalid memory address or nil pointer dereference
[signal 0xc0000005 code=0x0 addr=0x58 pc=0x7ff75be2f355]

goroutine 32748 [running]:
github.com/livepeer/go-livepeer/eth/watchers.(*UnbondingWatcher).handleBlockEvents(0xc002c8ffd0, {0xc000882100, 0x1c, 0x0})
        D:/a/go-livepeer/go-livepeer/eth/watchers/unbondingwatcher.go:74 +0x55
created by github.com/livepeer/go-livepeer/eth/watchers.(*UnbondingWatcher).Watch
        D:/a/go-livepeer/go-livepeer/eth/watchers/unbondingwatcher.go:62 +0x2af
```

### Additional contract requirements

When a block event is enriched successfully, its emitted block header must include the fetched L1 block number while retaining the original header data, including its logs.

If fetching the L1 block number fails, the emitted event must retain its original, non-nil block header unchanged.
