Unable to decode byte array
<!-- Please answer these questions before submitting your issue. Thanks! -->

### What version of Genji are you using?

```go
	github.com/genjidb/genji v0.8.1-0.20201027130408-3de6bdeb29e3
```

### Does this issue reproduce with the latest release?

I think it should reproduce, because responsible code is unaffected.

### What did you do?

```go
package main

import (
	"fmt"

	"github.com/genjidb/genji"
	"github.com/genjidb/genji/document"
)

func main() {
	db, err := genji.Open(":memory:")
	if err != nil {
		panic(err)
	}

	defer db.Close()

	err = db.Exec("CREATE TABLE foo")
	if err != nil {
		panic(err)
	}

	array := [4]uint8{1, 2, 3, 4}

	err = db.Exec("INSERT INTO foo (bar) VALUES (?)", &array)
	if err != nil {
		panic(err)
	}

	doc, err := db.QueryDocument("SELECT bar FROM foo")
	if err != nil {
		panic(err)
	}

	var dst [4]uint8
	err = document.Scan(doc, &dst)
	if err != nil {
		panic(err)
	}
	fmt.Printf("%v\n", dst)

}
```

### What did you expect to see?

```sh
[1 2 3 4]
```

### What did you see instead?

```sh
panic: unsupported type reflect.Value. Invalid type

goroutine 1 [running]:
main.main()
	/home/dio/junk/genji_tests/main.go:38 +0x374
```

### What Go version and environment are you using?

<pre>
$ go version
go version go1.15.2 linux/amd64
</pre>

<details><summary><code>go env</code> Output</summary><br><pre>
$ go env
GO111MODULE=""
GOARCH="amd64"
GOBIN=""
GOCACHE="/home/dio/.cache/go-build"
GOENV="/home/dio/.config/go/env"
GOEXE=""
GOFLAGS=""
GOHOSTARCH="amd64"
GOHOSTOS="linux"
GOINSECURE=""
GOMODCACHE="/home/dio/go/pkg/mod"
GOOS="linux"
GOPATH="/home/dio/go"
GOPRIVATE="gitlab.etecs.ru"
GOPROXY="https://proxy.golang.org,direct"
GOROOT="/usr/lib/go"
GOSUMDB="sum.golang.org"
GOTMPDIR=""
GOTOOLDIR="/usr/lib/go/pkg/tool/linux_amd64"
GCCGO="gccgo"
AR="ar"
CC="gcc"
CXX="g++"
CGO_ENABLED="1"
GOMOD="/home/dio/junk/genji_tests/go.mod"
CGO_CFLAGS="-g -O2"
CGO_CPPFLAGS=""
CGO_CXXFLAGS="-g -O2"
CGO_FFLAGS="-g -O2"
CGO_LDFLAGS="-g -O2"
PKG_CONFIG="pkg-config"
GOGCCFLAGS="-fPIC -m64 -pthread -fmessage-length=0 -fdebug-prefix-map=/tmp/go-build716115602=/tmp/go-build -gno-record-gcc-switches"
</pre></details>

### Little research

It seems that genji has code for encoding arrays as specific case in switch (document/create.go:240), but deconding is lacking something.

If we look at document/scan.go:337 we can found case that it intended to handle slices. Code seems to be able to work with array more or less. [HIDDEN]

### Additional contract requirements

- Scanning a stored byte value into a fixed-size Go byte array must succeed and preserve the bytes.
- A fixed-size non-byte Go array must be scannable from a compatible Genji array value, preserving its elements.
- Supporting fixed-size arrays must not break scanning into slices of document elements or pointers to those elements.
