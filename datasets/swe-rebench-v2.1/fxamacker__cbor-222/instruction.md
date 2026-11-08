bug: Validate CBOR tag content type if tag number is 0 or 1, even when TimeTag = DecTagIgnored
### What version of fxamacker/cbor are you using?
v2.2.0

### Does this issue reproduce with the latest release?
Yes.

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
GOGCCFLAGS="-fPIC -m64 -pthread -fmessage-length=0 -fdebug-prefix-map=/tmp/go-build282002194=/tmp/go-build -gno-record-gcc-switches"
</pre></details>

### What did you do?

Decode CBOR time tag (tag number 0 or 1) with inappropriate content type to time.Time.

Decoding option for TimeTag is DecTagIgnored by default.

```
func main() {
	// CBOR tag 0 should be followed by string content; otherwise, it is invalid.
	cborData, _ := hex.DecodeString("c01a514b67b0") // 0(1363896240)
	var tm time.Time
	if err := cbor.Unmarshal(cborData, &tm); err == nil {
		fmt.Printf("Unmarshal(0x%x) didn't return error\n", cborData)
	}
}
```

### What did you expect to see?
Decoding CBOR time tag (tag number 0 or 1) with inappropriate content type should return error.

### What did you see instead?

When TimeTag = DecTagIgnored, data type validation isn't performed for CBOR time content when tag number is 0 or 1.  It should only skip validation of CBOR time content for other tag numbers.

Decoding CBOR time tag (tag number 0 or 1) with inappropriate content type doesn't return error.
