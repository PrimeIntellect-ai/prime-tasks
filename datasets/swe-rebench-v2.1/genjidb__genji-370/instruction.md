Crash after deleting an index and running a query
Found this while opening #359

### What version of Genji are you using?

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
genji> INSERT INTO foo (b) VALUES (1);
genji> SELECT * FROM foo WHERE b = 1;
{
  "b": 1
}
genji> DROP INDEX idx_foo_a;
genji> EXPLAIN SELECT * FROM foo WHERE a = [1,2,3];
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x18 pc=0x43cec34]
```
<details><summary><code>stacktrace</code> Output</summary><br><pre>
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x18 pc=0x43cec34]

goroutine 7 [running]:
github.com/genjidb/genji/database.(*Catalog).GetTable(0xc0000100b8, 0xc0002c6000, 0xc00042205b, 0x3, 0x0, 0x471ad00, 0xc000473a80)
	/Users/tech/code/src/github.com/genjidb/genji/database/catalog.go:94 +0x1b4
github.com/genjidb/genji/database.(*Transaction).GetTable(...)
	/Users/tech/code/src/github.com/genjidb/genji/database/transaction.go:114
github.com/genjidb/genji/planner.RemoveUnnecessaryDistinctNodeRule(0xc000406030, 0xc0002c6000, 0xc000406030, 0x0, 0x0)
	/Users/tech/code/src/github.com/genjidb/genji/planner/optimizer.go:302 +0xa8
github.com/genjidb/genji/planner.Optimize(0xc000406030, 0xc0002c6000, 0x18, 0x4719f60, 0xc00008e240)
	/Users/tech/code/src/github.com/genjidb/genji/planner/optimizer.go:29 +0x7c
github.com/genjidb/genji/planner.(*ExplainStmt).Run(0xc000406050, 0xc0002c6000, 0x4a3c3f0, 0x0, 0x0, 0x0, 0x0, 0xc000473bf0, 0x405058c, 0x0, ...)
	/Users/tech/code/src/github.com/genjidb/genji/planner/explain.go:26 +0x85
github.com/genjidb/genji/query.Query.Run(0xc000406060, 0x1, 0x1, 0x0, 0x0, 0x47191a0, 0xc00052e000, 0xc00030e120, 0x4a3c3f0, 0x0, ...)
	/Users/tech/code/src/github.com/genjidb/genji/query/query.go:66 +0x214
github.com/genjidb/genji.(*DB).Query(0xc000492040, 0xc0001d8900, 0x2c, 0x0, 0x0, 0x0, 0x2c, 0xc000069da0, 0x40546e7)
	/Users/tech/code/src/github.com/genjidb/genji/db.go:101 +0x18a
github.com/genjidb/genji/cmd/genji/shell.(*Shell).runQuery(0xc00013a360, 0x47191a0, 0xc00052e000, 0xc0001d8900, 0x2c, 0x0, 0x0)
	/Users/tech/code/src/github.com/genjidb/genji/cmd/genji/shell/shell.go:521 +0xb1
github.com/genjidb/genji/cmd/genji/shell.(*Shell).executeInput(0xc00013a360, 0x47191a0, 0xc00052e000, 0xc0001d8900, 0x2c, 0x0, 0x0)
	/Users/tech/code/src/github.com/genjidb/genji/cmd/genji/shell/shell.go:441 +0x2a5
github.com/genjidb/genji/cmd/genji/shell.(*Shell).runExecutor(0xc00013a360, 0x47191a0, 0xc00007eac0, 0xc00002c1e0, 0x0, 0x0)
	/Users/tech/code/src/github.com/genjidb/genji/cmd/genji/shell/shell.go:221 +0x1cd
github.com/genjidb/genji/cmd/genji/shell.Run.func4(0x0, 0x0)
	/Users/tech/code/src/github.com/genjidb/genji/cmd/genji/shell/shell.go:164 +0x45
golang.org/x/sync/errgroup.(*Group).Go.func1(0xc000113cb0, 0xc000113ce0)
	/Users/tech/code/pkg/mod/golang.org/x/sync@v0.0.0-20201207232520-09787c993a3a/errgroup/errgroup.go:57 +0x59
created by golang.org/x/sync/errgroup.(*Group).Go
	/Users/tech/code/pkg/mod/golang.org/x/sync@v0.0.0-20201207232520-09787c993a3a/errgroup/errgroup.go:54 +0x66

</pre></details>


### What did you expect to see?

No crash.

### What did you see instead?

A crash!

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

### Additional contract requirements

After `DROP INDEX idx_foo_a`, running `EXPLAIN SELECT * FROM foo WHERE a = [1,2,3]` must complete without panicking and return a query plan (i.e. it must not return an error).
