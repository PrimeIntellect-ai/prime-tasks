bug: encoding uninitialized cbor.(Raw)Tag returns malformed CBOR data
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

Encode uninitialized cbor.(Raw)Tag.

```
var tag cbor.Tag
b, err := cbor.Marshal(tag)
fmt.Printf("Marshal(%+v) returns 0x%x, error %v\n", tag, b, err)
// Marshal({Number:0 Content:<nil>}) returns 0xc0f6, error <nil>

var rtag cbor.RawTag
b, err = cbor.Marshal(rtag)
fmt.Printf("Marshal(%+v) returns 0x%x, error %v\n", rtag, b, err)
// Marshal({Number:0 Content:[]}) returns 0xc0, error <nil>
```

### What did you expect to see?

Encoding uninitialized cbor.(Raw)Tag should return either valid CBOR data or error.

### What did you see instead?

See comments in code snippet in previous section.
