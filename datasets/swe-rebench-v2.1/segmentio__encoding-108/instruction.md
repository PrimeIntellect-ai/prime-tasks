json: stack overflow when encoding cyclic structures
Encoding a cyclic data structure results in a stack overflow. This is an invalid operation, but the behavior here is different than the stdlib that detects it and returns an error.

---

Program to reproduce:

```go
package main

import (
	"fmt"

	"github.com/segmentio/encoding/json"
)

type Foo struct {
	Bar *Bar
}

type Bar struct {
	Foo *Foo
}

func main() {
	f := &Foo{}
	b := &Bar{}
	f.Bar = b
	b.Foo = f

	_, err := json.Marshal(f)
	fmt.Println(err)
}
```

Crash in that example:

```
$ go run main.go
runtime: goroutine stack exceeds 1000000000-byte limit
runtime: sp=0xc0201603e0 stack=[0xc020160000, 0xc040160000]
fatal error: stack overflow

runtime stack:
runtime.throw({0x4eafe9, 0x59f520})
	/home/thomas/src/github.com/golang/go/src/runtime/panic.go:1198 +0x71
runtime.newstack()
	/home/thomas/src/github.com/golang/go/src/runtime/stack.go:1088 +0x5ac
runtime.morestack()
	/home/thomas/src/github.com/golang/go/src/runtime/asm_amd64.s:461 +0x8b

goroutine 1 [running]:
github.com/segmentio/encoding/json.encoder.encodeStruct({0x3}, {0xc002568000, 0x873eaf, 0x8ac000}, 0xc00000e030, 0xc00007e240)
	/home/thomas/pkg/mod/github.com/segmentio/encoding@v0.3.0/json/encode.go:758 +0x47a fp=0xc0201603f0 sp=0xc0201603e8 pc=0x4c185a
github.com/segmentio/encoding/json.constructStructEncodeFunc.func1({0x0}, {0xc002568000, 0x0, 0x0}, 0x0)
	/home/thomas/pkg/mod/github.com/segmentio/encoding@v0.3.0/json/codec.go:497 +0x25 fp=0xc020160430 sp=0xc0201603f0 pc=0x4ada05
github.com/segmentio/encoding/json.encoder.encodePointer({0x0}, {0xc002568000, 0x0, 0x0}, 0x0, {0x0, 0x0}, 0x0)
	/home/thomas/pkg/mod/github.com/segmentio/encoding@v0.3.0/json/encode.go:818 +0x7c fp=0xc020160470 sp=0xc020160430 pc=0x4c19fc
github.com/segmentio/encoding/json.constructPointerEncodeFunc.func1({0x0}, {0xc002568000, 0x0, 0x0}, 0x0)
	/home/thomas/pkg/mod/github.com/segmentio/encoding@v0.3.0/json/codec.go:738 +0x2a fp=0xc0201604c0 sp=0xc020160470 pc=0x4af5ea
github.com/segmentio/encoding/json.encoder.encodeStruct({0x0}, {0xc002568000, 0x873ea8, 0x0}, 0xc00000e028, 0xc00007e1e0)
	/home/thomas/pkg/mod/github.com/segmentio/encoding@v0.3.0/json/encode.go:789 +0x307 fp=0xc020160598 sp=0xc0201604c0 pc=0x4c16e7
github.com/segmentio/encoding/json.constructStructEncodeFunc.func1({0x0}, {0xc002568000, 0x0, 0x0}, 0x0)
	/home/thomas/pkg/mod/github.com/segmentio/encoding@v0.3.0/json/codec.go:497 +0x25 fp=0xc0201605d8 sp=0xc020160598 pc=0x4ada05
github.com/segmentio/encoding/json.encoder.encodePointer({0x0}, {0xc002568000, 0x0, 0x0}, 0x0, {0x0, 0x0}, 0x0)
	/home/thomas/pkg/mod/github.com/segmentio/encoding@v0.3.0/json/encode.go:818 +0x7c fp=0xc020160618 sp=0xc0201605d8 pc=0x4c19fc
...additional frames elided...
exit status 2
```

Output using stdlib's `encoding/json`:

```
$ go run main.go
json: unsupported value: encountered a cycle via *main.Foo
```

Stdlib implementation: https://cs.opensource.google/go/go/+/refs/tags/go1.17.3:src/encoding/json/encode.go;l=784-793;drc=refs%2Ftags%2Fgo1.17.3

### Additional contract requirements

- When encoding a cyclic data structure, `Marshal` must return an error of type `*UnsupportedValueError`.
