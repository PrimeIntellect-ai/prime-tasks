WriteBatch.Flush panics if called twice
I understand that flushing twice doesn't make sense, since a batch can only be flushed once, but the second call should error with a helpful message instead of panicking.

```
$ go version
go version devel +152ffca82f Mon Jun 29 08:06:32 2020 +0000 linux/amd64
$ go list -m github.com/dgraph-io/badger/v2
github.com/dgraph-io/badger/v2 v2.0.3
$ cat main.go
package main

import (
	"io/ioutil"
	"os"

	"github.com/dgraph-io/badger/v2"
)

func main() {
	dir, err := ioutil.TempDir("", "badger-test")
	if err != nil {
		panic(err)
	}
	defer os.RemoveAll(dir)
	db, err := badger.Open(badger.DefaultOptions(dir))
	if err != nil {
		panic(err)
	}
	defer db.Close()

	wb := db.NewWriteBatch()
	wb.Flush()
	wb.Flush()
}
$ go run main.go
badger 2020/06/30 18:36:15 INFO: All 0 tables opened in 0s
badger 2020/06/30 18:36:15 INFO: Got compaction priority: {level:0 score:1.73 dropPrefix:[]}
panic: send on closed channel

goroutine 1 [running]:
github.com/dgraph-io/badger/v2/y.(*Throttle).Do(0xc0000200c0, 0x6e7260, 0xc0000200c0)
	/home/mvdan/go/pkg/mod/github.com/dgraph-io/badger/v2@v2.0.3/y/y.go:260 +0xc9
github.com/dgraph-io/badger/v2.(*WriteBatch).commit(0xc000020180, 0x0, 0x0)
	/home/mvdan/go/pkg/mod/github.com/dgraph-io/badger/v2@v2.0.3/batch.go:141 +0x45
github.com/dgraph-io/badger/v2.(*WriteBatch).Flush(0xc000020180, 0x0, 0x0)
	/home/mvdan/go/pkg/mod/github.com/dgraph-io/badger/v2@v2.0.3/batch.go:155 +0x45
main.main()
	/home/mvdan/src/test/main.go:24 +0x1fa
exit status 2
```
