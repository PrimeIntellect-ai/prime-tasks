bug: encoding cbor.RawTag with empty content returns malformed CBOR data
### What version of fxamacker/cbor are you using?

v2.2.0

### Does this issue reproduce with the latest release?

Yes

### What OS and CPU architecture are you using (`go env`)?

<details><summary><code>go env</code> Output</summary><br><pre>
$ go env
GOARCH="amd64"
GOBIN=""
GOCACHE="/home/user/.cache/go-build"
GOEXE=""
GOFLAGS=""
GOHOSTARCH="amd64"
GOHOSTOS="linux"
GOOS="linux"
GOPATH="/home/user/go"
GOPROXY=""
GORACE=""
GOROOT="/usr/local/go"
GOTMPDIR=""
GOTOOLDIR="/usr/local/go/pkg/tool/linux_amd64"
GCCGO="gccgo"
CC="gcc"
CXX="g++"
CGO_ENABLED="1"
GOMOD=""
CGO_CFLAGS="-g -O2"
CGO_CPPFLAGS=""
CGO_CXXFLAGS="-g -O2"
CGO_FFLAGS="-g -O2"
CGO_LDFLAGS="-g -O2"
PKG_CONFIG="pkg-config"
GOGCCFLAGS="-fPIC -m64 -pthread -fmessage-length=0 -fdebug-prefix-map=/tmp/go-build778508732=/tmp/go-build -gno-record-gcc-switches"
</pre></details>

### What did you do?

Encode cbor.RawTag with empty content.

```
rtag := cbor.RawTag{Number: 100} // RawTag.Content is empty
b, err = cbor.Marshal(rtag)
fmt.Printf("Marshal(%+v) returns 0x%x, error %v\n", rtag, b, err)
// Marshal({Number:100 Content:[]}) returns 0xd864, error <nil>
```

### What did you expect to see?

Encoding cbor.RawTag should return either valid CBOR data or error.

### What did you see instead?

See comments in code snippet in previous section.
