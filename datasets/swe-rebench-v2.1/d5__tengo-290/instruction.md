bug + panic in  for-loop (for k,v in dict syntax)
Bug: the key `k` is not visible inside the func `f` in the loop ( therefore: `Runtime Error: invalid index type: undefined`)
```
fmt := import(`fmt`)
bug := func(){
    map := {a:1.0,b:2.0}
    for k,v in map{
        f := func(){
            fmt.println(map[k])
        }
        f()
    }
}
bug()
```
While this is a proper workaround:
```
fmt := import(`fmt`)
workaround := func(){
    map := {a:1.0,b:2.0}
    for k,v in map{
        key := k
        f := func(){
            fmt.println(map[key])
        }
        f()
    }
}
workaround()
```

This segfaults:
```
fmt := import(`fmt`)

segfault := func(){
    map := {a:1.0,b:2.0}
    for k,v in map{
        k := k
        f := func(){
            fmt.println(map[k])
        }
        f()
    }
}
segfault()
```
```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x68 pc=0x529f12]

goroutine 1 [running]:
github.com/d5/tengo/v2.ToString(0x0, 0x0, 0xc00001a477, 0x7, 0xc0000c62e8)
    /go/src/github.com/d5/tegno/tengo.go:71 +0x62
github.com/d5/tengo/v2.(*Map).IndexGet(0xc00000e758, 0x0, 0x0, 0x63d5e0, 0xc0000da150, 0x0, 0x0)
    /go/src/github.com/d5/tegno/objects.go:1239 +0x39
github.com/d5/tengo/v2.(*VM).run(0xc0000f0000)
    /go/src/github.com/d5/tegno/vm.go:352 +0x394f
github.com/d5/tengo/v2.(*VM).Run(0xc0000f0000, 0xc0000f0000, 0x400)
    /go/src/github.com/d5/tegno/vm.go:77 +0xcf
main.CompileAndRun(0xc00000e6c0, 0xc0000ce000, 0xc4, 0x2c4, 0x7ffccbe0b94a, 0x29, 0x0, 0xc000062180)
    /go/src/github.com/d5/tegno/cmd/tengo/main.go:134 +0x1e8
main.main()
    /go/src/github.com/d5/tegno/cmd/tengo/main.go:73 +0x28b
```

### Additional contract requirements

- Inside a `for k, v in` loop over a map, a function literal defined in the loop body must be able to read the loop key `k` and use it to index the map (for example `map[k]`).
- Redeclaring the loop key inside the loop body (`k := k`) and then using that redeclared variable from a nested function is outside this request; it is not required to work.
