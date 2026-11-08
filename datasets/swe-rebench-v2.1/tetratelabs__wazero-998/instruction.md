Deadlock in compilation cache
**Describe the bug**
Use of the compilation cache between wazero versions seems to be able to cause a deadlock when the cache is cleaned.

**To Reproduce**
```
$ go mod init example.com/wazero-dl
go: creating new go.mod: module example.com/wazero-dl
$ cat <<EOF > main.go
package main

import (
        "context"
        "log"
        "os"
        "time"

        "github.com/tetratelabs/wazero"
        "github.com/tetratelabs/wazero/experimental"
)

func main() {
        bin, err := os.ReadFile(os.Args[1])
        if err != nil {
                log.Panicln(err)
        }

        ctx, err := experimental.WithCompilationCacheDirName(context.Background(), ".build")
        if err != nil {
                log.Panicln(err)
        }
        r := wazero.NewRuntime(ctx)
        defer r.Close(ctx) // This closes everything this Runtime created.

        start := time.Now()
        if _, err = r.CompileModule(ctx, bin); err != nil {
                log.Panicln(err)
        }
        log.Printf("CompileModule took %dms", time.Since(start).Milliseconds())
}
EOF
$ go get github.com/tetratelabs/wazero@3f578ddac3897b1435fbb1fe7e807676f062e4b1
go: added github.com/tetratelabs/wazero v1.0.0-pre.5.0.20221229073945-3f578ddac389
$ echo '(module (func (export "main") (result i32) i32.const 42 return))' | wat2wasm - -o simple.wasm
$ go run . simple.wasm
2022/12/29 15:16:56 CompileModule took 0ms
$ go get github.com/tetratelabs/wazero@62be68dfc5f477d766d9dcfe422dcfc498c7bbfd
go: downloading github.com/tetratelabs/wazero v1.0.0-pre.5.0.20221229092947-62be68dfc5f4
go: upgraded github.com/tetratelabs/wazero v1.0.0-pre.5.0.20221229073945-3f578ddac389 => v1.0.0-pre.5.0.20221229092947-62be68dfc5f4
$ go run . simple.wasm
fatal error: all goroutines are asleep - deadlock!

goroutine 1 [semacquire]:
sync.runtime_SemacquireMutex(0x104425620?, 0xa0?, 0x1400013db68?)
        /Users/robbert/.gimme/versions/go1.19.3.darwin.arm64/src/runtime/sema.go:77 +0x24
sync.(*RWMutex).Lock(0x101400013dba8?)
        /Users/robbert/.gimme/versions/go1.19.3.darwin.arm64/src/sync/rwmutex.go:152 +0x100
github.com/tetratelabs/wazero/internal/compilationcache.(*fileCache).Delete(0x14000115170, {0xc1, 0x83, 0xb6, 0x11, 0xda, 0x74, 0xfe, 0xc0, 0x46, ...})
        /Users/robbert/go/pkg/mod/github.com/tetratelabs/wazero@v1.0.0-pre.5.0.20221229092947-62be68dfc5f4/internal/compilationcache/file_cache.go:92 +0x3c
github.com/tetratelabs/wazero/internal/engine/compiler.(*engine).getCodesFromCache(0x1400010c0a0, 0x14000102680)
        /Users/robbert/go/pkg/mod/github.com/tetratelabs/wazero@v1.0.0-pre.5.0.20221229092947-62be68dfc5f4/internal/engine/compiler/engine_cache.go:84 +0x18c
github.com/tetratelabs/wazero/internal/engine/compiler.(*engine).getCodes(0x1400013dd58?, 0x1043312f4?)
        /Users/robbert/go/pkg/mod/github.com/tetratelabs/wazero@v1.0.0-pre.5.0.20221229092947-62be68dfc5f4/internal/engine/compiler/engine_cache.go:35 +0x34
github.com/tetratelabs/wazero/internal/engine/compiler.(*engine).CompileModule(0x1400010c0a0, {0x1044482b8, 0x14000115110}, 0x14000102680, {0x0, 0x0, 0x200?})
        /Users/robbert/go/pkg/mod/github.com/tetratelabs/wazero@v1.0.0-pre.5.0.20221229092947-62be68dfc5f4/internal/engine/compiler/engine.go:488 +0x3c
github.com/tetratelabs/wazero.(*runtime).CompileModule(0x140001260c0, {0x1044482b8, 0x14000115110}, {0x14000164000, 0x26, 0x200})
        /Users/robbert/go/pkg/mod/github.com/tetratelabs/wazero@v1.0.0-pre.5.0.20221229092947-62be68dfc5f4/runtime.go:200 +0x258
main.main()
        $/main.go:27 +0x160
exit status 2
```
**Expected behavior**
No deadlock.

**Screenshots**
N/a

**Environment (please complete the relevant information):**
- Go version: 1.19.3
- wazero Version: see repro, experienced on other commits too (se below).
- Host architecture: arm64
- Runtime mode: n/a

**Additional context**
Narrowed this down to a simple example from what I'd previously mentioned in https://github.com/tetratelabs/wazero/issues/939#issuecomment-1358589231. I could reproduce it it for the sha's mentioned there too but for the repo I used HEAD & HEAD~ to make sure this was still an issue.

### Additional contract requirements

- The cache deserialization function must be declared in package `internal/engine/compiler` as `deserializeCodes(wazeroVersion string, reader io.ReadCloser) (codes []*code, staleCache bool, err error)`.
- When the cache stream is empty, the returned error message must be exactly `compilationcache: error reading header: EOF`.
