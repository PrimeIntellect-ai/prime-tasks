Request.Attributes() can panic when called with the Attr slice empty
As mentioned in the title, I got a panic in production.

Is this supposed to happen and am I supposed to check the byte slice myself prior to calling `Attributes()`, or can we just check that in the function (that would be my preference) ? Or is the byte slice always supposed to be filled? (My guess this is some weird client that did not comply to the SFTP standards).

Panic here:

```
panic: runtime error: index out of range [3] with length 0

goroutine 261287 [running]:
github.com/pkg/sftp.unmarshalUint32(...)
        /go/pkg/mod/github.com/pkg/sftp@v1.10.1/packet.go:73
github.com/pkg/sftp.getFileStat(0x138, 0xc0016125df, 0x4, 0x4, 0x3, 0x8, 0x30, 0x8)
        /go/pkg/mod/github.com/pkg/sftp@v1.10.1/attrs.go:118 +0x53d
github.com/pkg/sftp.(*Request).Attributes(...)
        /go/pkg/mod/github.com/pkg/sftp@v1.10.1/request-attrs.go:61
source-dir/sftp.(*RequestHandler).handleSetStat(0xc001324cc0, 0xc000dcd620, 0x6, 0x6, 0xc0006fe540, 0xc0011d1030, 0x6, 0x6)
        /source-dir/sftp/request_handler.go:296 +0x65
source-dir/sftp.(*RequestHandler).Filecmd(0xc001324cc0, 0xc0006fe540, 0xc00045bba0, 0x10)
        /source-dir/sftp/request_handler.go:276 +0x6e2
github.com/pkg/sftp.filecmd(0xfd6d00, 0xc001324cc0, 0xc0006fe540, 0xfe00c0, 0xc0023aba40, 0xfdf180, 0x40df9b)
        /go/pkg/mod/github.com/pkg/sftp@v1.10.1/request.go:267 +0xd4
github.com/pkg/sftp.(*Request).call(0xc0006fe540, 0xfd6d40, 0xc001324cc0, 0xfd6d60, 0xc001324cc0, 0xfd6d00, 0xc001324cc0, 0xfd6d20, 0xc001324cc0, 0xfe00c0, ...)
        /go/pkg/mod/github.com/pkg/sftp@v1.10.1/request.go:162 +0x389
github.com/pkg/sftp.(*RequestServer).packetWorker(0xc001161000, 0xfec780, 0xc000d2d180, 0xc000da4600, 0x70189a101, 0xc00082c7c8)
        /go/pkg/mod/github.com/pkg/sftp@v1.10.1/request-server.go:187 +0x559
github.com/pkg/sftp.(*RequestServer).Serve.func1.1(0xc000c07030, 0xc001161000, 0xfec780, 0xc000d2d180, 0xc000da4600)
        /go/pkg/mod/github.com/pkg/sftp@v1.10.1/request-server.go:98 +0x89
created by github.com/pkg/sftp.(*RequestServer).Serve.func1
        /go/pkg/mod/github.com/pkg/sftp@v1.10.1/request-server.go:96 +0xa1
```
