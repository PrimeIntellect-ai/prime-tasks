Slice out of bound error in raft log
Got the following error when running @jiangxinmeng1's TestSnapshot.

```
{"level":"panic","ts":"2021-12-24 13:21:56.025","logger":"cube.store","caller":"raftstore/replica.go:617","msg":"slice[9,11) out of bound [9,8]","case":"TestSnapshot","store":"node-2","store-id":1022,"shard-id":2,"replica-id":1104}
panic: slice[9,11) out of bound [9,8]

goroutine 2896 [running]:
go.uber.org/zap/zapcore.(*CheckedEntry).Write(0x1400bd67b00, {0x0, 0x0, 0x0})
  /Users/lni/go/pkg/mod/go.uber.org/zap@v1.19.1/zapcore/entry.go:232 +0x3c8
go.uber.org/zap.(*SugaredLogger).log(0x14011d22ad0, 0x4, {0x1017323e3, 0x21}, {0x1400728b180, 0x4, 0x4}, {0x0, 0x0, 0x0})
  /Users/lni/go/pkg/mod/go.uber.org/zap@v1.19.1/sugar.go:227 +0xfc
go.uber.org/zap.(*SugaredLogger).Panicf(...)
  /Users/lni/go/pkg/mod/go.uber.org/zap@v1.19.1/sugar.go:159
github.com/matrixorigin/matrixcube/raftstore.(*etcdRaftLoggerAdapter).Panicf(0x14011d22ad8, {0x1017323e3, 0x21}, {0x1400728b180, 0x4, 0x4})
  /Users/lni/src/matrixcube/raftstore/replica.go:617 +0x64
go.etcd.io/etcd/raft/v3.(*raftLog).mustCheckOutOfBounds(0x14014eeff10, 0x9, 0xb)
  /Users/lni/go/pkg/mod/github.com/matrixorigin/etcd/raft/v3@v3.5.1-0.20210824022435-0203115049c2/log.go:392 +0x2c8
go.etcd.io/etcd/raft/v3.(*raftLog).slice(0x14014eeff10, 0x9, 0xb, 0x0)
  /Users/lni/go/pkg/mod/github.com/matrixorigin/etcd/raft/v3@v3.5.1-0.20210824022435-0203115049c2/log.go:341 +0x38
go.etcd.io/etcd/raft/v3.(*raftLog).nextEnts(0x14014eeff10)
  /Users/lni/go/pkg/mod/github.com/matrixorigin/etcd/raft/v3@v3.5.1-0.20210824022435-0203115049c2/log.go:183 +0x68
go.etcd.io/etcd/raft/v3.newReady(0x14007894f20, 0x140094fada0, {0x2, 0x0, 0xa})
  /Users/lni/go/pkg/mod/github.com/matrixorigin/etcd/raft/v3@v3.5.1-0.20210824022435-0203115049c2/node.go:562 +0x64
go.etcd.io/etcd/raft/v3.(*RawNode).readyWithoutAccept(...)
  /Users/lni/go/pkg/mod/github.com/matrixorigin/etcd/raft/v3@v3.5.1-0.20210824022435-0203115049c2/rawnode.go:134
go.etcd.io/etcd/raft/v3.(*RawNode).Ready(0x140075a4360)
  /Users/lni/go/pkg/mod/github.com/matrixorigin/etcd/raft/v3@v3.5.1-0.20210824022435-0203115049c2/rawnode.go:126 +0x6c
github.com/matrixorigin/matrixcube/raftstore.(*replica).getRaftReady(...)
  /Users/lni/src/matrixcube/raftstore/replica_event_raft_ready.go:45
github.com/matrixorigin/matrixcube/raftstore.(*replica).handleRaftReady(0x1401aca9800, 0x14012826750)
  /Users/lni/src/matrixcube/raftstore/replica_event_raft_ready.go:36 +0x34
github.com/matrixorigin/matrixcube/raftstore.(*replica).handleEvent(0x1401aca9800, 0x14012826750)
  /Users/lni/src/matrixcube/raftstore/replica_event_loop.go:234 +0x208
github.com/matrixorigin/matrixcube/raftstore.(*replicaWorker).handleEvent(0x14012826780, {0x101cd8fc0, 0x1401aca9800})
  /Users/lni/src/matrixcube/raftstore/worker_pool.go:114 +0x58
github.com/matrixorigin/matrixcube/raftstore.(*replicaWorker).workerMain(0x14012826780)
  /Users/lni/src/matrixcube/raftstore/worker_pool.go:91 +0xb4
github.com/matrixorigin/matrixcube/raftstore.newReplicaWorker.func1()
  /Users/lni/src/matrixcube/raftstore/worker_pool.go:72 +0x28
github.com/lni/goutils/syncutil.(*Stopper).runWorker.func1(0x14013b4a1a0, 0x1401abca5e0, {0x0, 0x0}, 0x1401aa7b0d0)
  /Users/lni/go/pkg/mod/github.com/lni/goutils@v1.3.0/syncutil/stopper.go:79 +0xc0
created by github.com/lni/goutils/syncutil.(*Stopper).runWorker
  /Users/lni/go/pkg/mod/github.com/lni/goutils@v1.3.0/syncutil/stopper.go:74 +0x88
FAIL  github.com/matrixorigin/matrixone/pkg/vm/driver/test  37.014s
FAIL
```

### Additional contract requirements

- When an initial snapshot is handled with an existing raft-log range from index 101 through 110, preserve that range: the first log index must remain 101 and the last log index must remain 110 after the event is handled.
