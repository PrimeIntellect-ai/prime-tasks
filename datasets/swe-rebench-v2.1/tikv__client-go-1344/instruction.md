nil panic once meet quota limit error
![image](https://github.com/tikv/client-go/assets/6428910/db85811b-6aab-43dd-bbe2-8e7b0fc95d13)

![image](https://github.com/tikv/client-go/assets/6428910/49901dae-fa22-4bac-b19d-f6f092032559)

```
[2024/05/15 17:57:51.732 +08:00] [ERROR] [coprocessor.go:1152] ["copIteratorWork meet panic"] [r="runtime error: invalid memory address or nil pointer dereference"] ["stack trace"="gi
thub.com/pingcap/tidb/pkg/store/copr.(*copIteratorWorker).handleTask.func1\n\t/data/nvme0n1/csn/program/go/tidb/pkg/store/copr/coprocessor.go:1154\nruntime.gopanic\n\t/snap/go/10585/s
rc/runtime/panic.go:770\nruntime.panicmem\n\t/snap/go/10585/src/runtime/panic.go:261\nruntime.sigpanic\n\t/snap/go/10585/src/runtime/signal_unix.go:881\ngithub.com/tikv/client-go/v2/i
nternal/locate.(*RegionRequestSender).sendReqToRegion\n\t/data/nvme0n1/csn/program/go/client-go/internal/locate/region_request.go:2118\ngithub.com/tikv/client-go/v2/internal/locate.(*
RegionRequestSender).SendReqCtx\n\t/data/nvme0n1/csn/program/go/client-go/internal/locate/region_request.go:1796\ngithub.com/tikv/client-go/v2/txnkv/txnsnapshot.(*ClientHelper).SendRe
qCtx\n\t/data/nvme0n1/csn/program/go/client-go/txnkv/txnsnapshot/client_helper.go:146\ngithub.com/pingcap/tidb/pkg/store/copr.(*copIteratorWorker).handleTaskOnce\n\t/data/nvme0n1/csn/
program/go/tidb/pkg/store/copr/coprocessor.go:1275\ngithub.com/pingcap/tidb/pkg/store/copr.(*copIteratorWorker).handleTask\n\t/data/nvme0n1/csn/program/go/tidb/pkg/store/copr/coproces
sor.go:1165\ngithub.com/pingcap/tidb/pkg/store/copr.(*copIteratorWorker).run\n\t/data/nvme0n1/csn/program/go/tidb/pkg/store/copr/coprocessor.go:828"]
```


the error.Cause may retrun nil:

https://github.com/tikv/client-go/blob/c40432e3abccd374ea0f6b945f95b925004b4e49/internal/locate/region_request.go#L2118

and

https://github.com/tikv/client-go/blob/c40432e3abccd374ea0f6b945f95b925004b4e49/internal/locate/region_request.go#L2214
