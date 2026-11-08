bug: Registering tag (TagSet.Add) with already registered tag number should be rejected
### What version of fxamacker/cbor are you using?
commit 3f759bc5919a222f159e5a9d5f715520d931cf3e

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
GOGCCFLAGS="-fPIC -m64 -pthread -fmessage-length=0 -fdebug-prefix-map=/tmp/go-build813183223=/tmp/go-build -gno-record-gcc-switches"
</pre></details>

### What did you do?
Use `TagSet.Add` to register two tags.  Both tags have the same tag number, but different content type.

```
func main() {
	type myBool bool
	type myInt int

	tags := cbor.NewTagSet()

	// Register tag number 100 and myBool content type.
	err := tags.Add(
		cbor.TagOptions{DecTag: cbor.DecTagRequired, EncTag: cbor.EncTagRequired},
		reflect.TypeOf(myBool(false)),
		100)
	if err != nil {
		fmt.Printf("Expected no error, got error %v\n", err)
	}

	// Register tag number 100 (again) and myInt content type.
	err = tags.Add(
		cbor.TagOptions{DecTag: cbor.DecTagRequired, EncTag: cbor.EncTagRequired},
		reflect.TypeOf(myInt(0)),
		100)
	if err == nil {
		fmt.Printf("Expected error, got no error\n")
	}
}
```

### What did you expect to see?
Registering tag with already registered tag number should return error.


### What did you see instead?
Registering tag with already registered tag number doesn't return error.
