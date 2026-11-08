bug: decoding CBOR null to cbor.Tag shouldn't return any error
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
GOGCCFLAGS="-fPIC -m64 -pthread -fmessage-length=0 -fdebug-prefix-map=/tmp/go-build203361724=/tmp/go-build -gno-record-gcc-switches"
</pre></details>

### What did you do?

Decode CBOR null to cbor.Tag.

### What did you expect to see?

Decoding CBOR null to cbor.Tag should be a no-op and return no error according to `Unmarshal` documentation.

```
To unmarshal CBOR null (0xf6) and undefined (0xf7) values into a slice/map/pointer, Unmarshal sets Go value to nil.  Because null is often used to mean "not present", unmarshalling CBOR null and undefined value into any other Go type has no effect and returns no error.
```

### What did you see instead?

Decoding CBOR null to cbor.Tag returns an error "cbor: cannot unmarshal primitives into Go value of type cbor.Tag".

### Notes

Decoding CBOR null to cbor.RawTag returns the same error.
