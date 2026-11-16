where condition do not match on indexed array field (equality comparison)
<!-- Please answer these questions before submitting your issue. Thanks! -->

### What version of Genji are you using?

Latest commit on the main branch

<pre>
$ genji version
Genji v0.11.0
Genji CLI (devel)
</pre>

### Does this issue reproduce with the latest release?

Yes

### What did you do?

```
~› genji
Opened an in-memory database.
Enter ".help" for usage hints.
genji> CREATE TABLE foo;
genji> CREATE INDEX idx_foo_a ON foo(a);
genji> INSERT INTO foo (a) VALUES ([1,2,3]);
genji> INSERT INTO foo (a) VALUES ([4,5,6]);
genji> SELECT * from foo;
{
  "a": [
    1,
    2,
    3
  ]
}
{
  "a": [
    4,
    5,
    6
  ]
}
genji> EXPLAIN SELECT * FROM foo WHERE a = [1,2,3];
{
  "plan": "indexScan(\"idx_foo_a\", [1, 2, 3])"
}
genji> SELECT * FROM foo WHERE a = [1,2,3];
genji>
```

### What did you expect to see?

```
genji> SELECT * FROM foo WHERE a = [1,2,3];
{
  "a": [
    1,
    2,
    3
  ]
}
genji>
```

### What did you see instead?

genji> SELECT * FROM foo WHERE a = [1,2,3];
genji>

### What Go version and environment are you using?

<pre>
$ go version
go version go1.15.8 darwin/amd64
</pre>

<details><summary><code>go env</code> Output</summary><br><pre>
$ go env
GO111MODULE="on"
GOARCH="amd64"
GOBIN="/Users/tech/code/bin"
GOCACHE="/Users/tech/Library/Caches/go-build"
GOENV="/Users/tech/Library/Application Support/go/env"
GOEXE=""
GOFLAGS=""
GOHOSTARCH="amd64"
GOHOSTOS="darwin"
GOINSECURE=""
GOMODCACHE="/Users/tech/code/pkg/mod"
GONOPROXY=""
GONOSUMDB=""
GOOS="darwin"
GOPATH="/Users/tech/code"
GOPRIVATE=""
GOPROXY="https://proxy.golang.org,direct"
GOROOT="/Users/tech/.asdf/installs/golang/1.15.8/go"
GOSUMDB="sum.golang.org"
GOTMPDIR=""
GOTOOLDIR="/Users/tech/.asdf/installs/golang/1.15.8/go/pkg/tool/darwin_amd64"
GCCGO="gccgo"
AR="ar"
CC="clang"
CXX="clang++"
CGO_ENABLED="1"
GOMOD="/dev/null"
CGO_CFLAGS="-g -O2"
CGO_CPPFLAGS=""
CGO_CXXFLAGS="-g -O2"
CGO_FFLAGS="-g -O2"
CGO_LDFLAGS="-g -O2"
PKG_CONFIG="pkg-config"
GOGCCFLAGS="-fPIC -m64 -pthread -fno-caret-diagnostics -Qunused-arguments -fmessage-length=0 -fdebug-prefix-map=/var/folders/xl/dfsx6nzs4cb2y40m555mlfjh0000gn/T/go-build752488097=/tmp/go-build -gno-record-gcc-switches -fno-common"

</pre></details>
