bug: RawTag.UnmarshalCBOR() panic with truncated tag
### What version of fxamacker/cbor are you using?

v2.7.0

### Does this issue reproduce with the latest release?

I haven’t tested.

### What OS and CPU architecture are you using (`go env`)?

```console
$ go env

GO111MODULE=''
GOARCH='arm64'
GOBIN=''
GOCACHE='/Users/tho/Library/Caches/go-build'
GOENV='/Users/tho/Library/Application Support/go/env'
GOEXE=''
GOEXPERIMENT=''
GOFLAGS=''
GOHOSTARCH='arm64'
GOHOSTOS='darwin'
GOINSECURE=''
GOMODCACHE='/Users/tho/go/pkg/mod'
GONOPROXY=''
GONOSUMDB=''
GOOS='darwin'
GOPATH='/Users/tho/go'
GOPRIVATE=''
GOPROXY='https://proxy.golang.org,direct'
GOROOT='/usr/local/go'
GOSUMDB='sum.golang.org'
GOTMPDIR=''
GOTOOLCHAIN='auto'
GOTOOLDIR='/usr/local/go/pkg/tool/darwin_arm64'
GOVCS=''
GOVERSION='go1.23.0'
GODEBUG=''
GOTELEMETRY='local'
GOTELEMETRYDIR='/Users/tho/Library/Application Support/go/telemetry'
GCCGO='gccgo'
GOARM64='v8.0'
AR='ar'
CC='clang'
CXX='clang++'
CGO_ENABLED='1'
GOMOD='/Users/tho/Code/github.com/veraison/cmw/go.mod'
GOWORK=''
CGO_CFLAGS='-O2 -g'
CGO_CPPFLAGS=''
CGO_CXXFLAGS='-O2 -g'
CGO_FFLAGS='-O2 -g'
CGO_LDFLAGS='-O2 -g'
PKG_CONFIG='pkg-config'
GOGCCFLAGS='-fPIC -arch arm64 -pthread -fno-caret-diagnostics -Qunused-arguments -fmessage-length=0 -ffile-prefix-map=/var/folders/st/1wblnvg95bg4p9hnzc6dwjzh0000gn/T/go-build1346977790=/tmp/go-build -gno-record-gcc-switches -fno-common'
```

### What did you do?

```go
{
    var v cbor.RawTag

    truncatedTag := []byte{0xda}

    err := v.UnmarshalCBOR(truncatedTag)

    checkErr(err)
}

```

### What did you expect to see?

An error from `UnmarshalCBOR`

### What did you see instead?

The following panic trace:

```
panic: runtime error: slice bounds out of range [:5] with capacity 1 [recovered]
	panic: runtime error: slice bounds out of range [:5] with capacity 1

panic({0x102b34b00?, 0x140000b61c8?})
	/usr/local/go/src/runtime/panic.go:785 +0x124
github.com/fxamacker/cbor/v2.(*decoder).getHead(0x140000fbaa8?)
	/Users/tho/go/pkg/mod/github.com/fxamacker/cbor/v2@v2.7.0/decode.go:2921 +0x1cc
github.com/fxamacker/cbor/v2.(*RawTag).UnmarshalCBOR(0x140000fbac8, {0x140000fbac7?, 0x140000fbad8?, 0x10291cd5c?})
	/Users/tho/go/pkg/mod/github.com/fxamacker/cbor/v2@v2.7.0/tag.go:39 +0x88
[...]
```

### Additional contract requirements

- For input `[]byte{0xda}`, `RawTag.UnmarshalCBOR` must return an error whose message begins with `unexpected EOF`.
- For input `[]byte{0xd8}` and input `[]byte{0xc0, 0x74, 0x32, 0x30, 0x31, 0x33, 0x2d, 0x30, 0x33, 0x2d, 0x32, 0x31, 0x54, 0x32, 0x30, 0x3a, 0x30, 0x34, 0x3a, 0x30, 0x30}`, the error message must begin with `unexpected EOF`.
