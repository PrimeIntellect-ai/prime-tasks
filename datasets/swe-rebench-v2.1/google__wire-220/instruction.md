Panic when calling wire.Struct with a non-struct first argument
Code like this:

```go
package main

import "github.com/google/wire"

type A struct {
	B string
}

func makeA(string) A {
	panic(wire.Build(wire.Struct(new(*A), "*")))
}
```

causes a panic like this:

```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x8 pc=0x57f376]

goroutine 1 [running]:
go/types.writeType(0xc0024a15f0, 0x776540, 0x0, 0x0, 0xc0002353a8, 0x1, 0x8)
        /home/gracenoah/.go/src/go/types/typestring.go:120 +0x6a6
go/types.WriteType(...)
        /home/gracenoah/.go/src/go/types/typestring.go:75
go/types.TypeString(0x776540, 0x0, 0x0, 0xc0001ccb40, 0x25)
        /home/gracenoah/.go/src/go/types/typestring.go:67 +0xb1
github.com/google/wire/internal/wire.processStructProvider(0xc0000ea280, 0xc002486aa0, 0xc00247d100, 0x6, 0x1, 0x75)
        /home/gracenoah/go/pkg/mod/github.com/google/wire@v0.3.0/internal/wire/parse.go:806 +0xb11
github.com/google/wire/internal/wire.(*objectCache).processExpr(0xc0021b3880, 0xc002486aa0, 0xc0001d6450, 0x5, 0x778ec0, 0xc00247d100, 0x0, 0x0, 0x20, 0x6d88a0, ...)
        /home/gracenoah/go/pkg/mod/github.com/google/wire@v0.3.0/internal/wire/parse.go:556 +0xb6e
github.com/google/wire/internal/wire.(*objectCache).processNewSet(0xc0021b3880, 0xc002486aa0, 0xc0001d6450, 0x5, 0xc00247d140, 0xc0021b38c0, 0x0, 0x0, 0x0, 0x0, ...)
        /home/gracenoah/go/pkg/mod/github.com/google/wire@v0.3.0/internal/wire/parse.go:592 +0x18c
github.com/google/wire/internal/wire.generateInjectors(0xc002486f50, 0xc0001dcd20, 0x2, 0xc00113f590, 0x29, 0x0, 0x0, 0xc0000ac010)
        /home/gracenoah/go/pkg/mod/github.com/google/wire@v0.3.0/internal/wire/wire.go:176 +0x9f4
github.com/google/wire/internal/wire.Generate(0x77a080, 0xc00008e000, 0xc000016064, 0x1d, 0xc000102000, 0x60, 0x60, 0xc0000ac010, 0x1, 0x1, ...)
        /home/gracenoah/go/pkg/mod/github.com/google/wire@v0.3.0/internal/wire/wire.go:99 +0x411
main.(*genCmd).Execute(0xc000077e78, 0x77a080, 0xc00008e000, 0xc0000a4120, 0x0, 0x0, 0x0, 0x30)
        /home/gracenoah/go/pkg/mod/github.com/google/wire@v0.3.0/cmd/wire/main.go:131 +0x247
main.main()
        /home/gracenoah/go/pkg/mod/github.com/google/wire@v0.3.0/cmd/wire/main.go:71 +0x4dc
exit status 2
```

_Originally posted by @gracenoah in https://github.com/google/wire/issues/201#issuecomment-547765661_

### Additional contract requirements

When `wire.Struct` receives a first argument that is not a pointer to a named struct (for example `new(*A)` where `A` is a struct), Wire generation must report an error rather than panic. The reported error must read `first argument to Struct must be a pointer to a named struct; found <type>`, prefixed by the position of the `wire.Struct` call, where `<type>` is the type of the first argument (for example `**example.com/foo.A`).
