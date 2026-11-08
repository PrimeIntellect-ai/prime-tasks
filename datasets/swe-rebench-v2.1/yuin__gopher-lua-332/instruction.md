Index out of range error in state.go's where function
1. What version of GopherLua are you using? :
This is the version written in go.mod:
` github.com/yuin/gopher-lua v0.0.0-20210529063254-f4c35e4016d9 // indirect`
2. What version of Go are you using? : go1.16.3 linux/amd64
3. What operating system and processor architecture are you using? : Ubuntu 20.04.1 LTS
4. What did you do? : While I was fuzzing gopher-lua, I am encountered with panic. This is the piece of code that I use.
```
package main

import (
    "github.com/yuin/gopher-lua"
    "fmt"
)

func main(){

data := "return  select(0)(select(1/9))"

L := lua.NewState()
defer L.Close()
if err := L.DoString(data); err != nil {
 fmt.Println(data)
}

}
```

5. What did you expect to see? : I think, it shouldn't be panicked.
6. What did you see instead? : I think, it should handle index out of range error. It might control index, which can not be negative number, before giving it as an argument.

This is my output:
```
panic: runtime error: index out of range [-1] [recovered]
 panic: runtime error: index out of range [-1]

goroutine 1 [running]:
github.com/yuin/gopher-lua.(*LState).where(0xc0001b4000, 0x0, 0xc00047ef00, 0xc000118001, 0x8)
 /home/fuzz/go/pkg/mod/github.com/yuin/gopher-lua@v0.0.0-20210529063254-f4c35e4016d9/state.go:735 +0x27e
github.com/yuin/gopher-lua.(*LState).Where(...)
 /home/fuzz/go/pkg/mod/github.com/yuin/gopher-lua@v0.0.0-20210529063254-f4c35e4016d9/auxlib.go:252
github.com/yuin/gopher-lua.(*LState).stackTrace(0xc0001b4000, 0x0, 0xc00018bd90, 0xc000180090)
 /home/fuzz/go/pkg/mod/github.com/yuin/gopher-lua@v0.0.0-20210529063254-f4c35e4016d9/state.go:747 +0x1d3
github.com/yuin/gopher-lua.(*LState).PCall.func1(0x581df0, 0xc0001b4000, 0xc000061ef0, 0x0, 0x0, 0x0)
 /home/fuzz/go/pkg/mod/github.com/yuin/gopher-lua@v0.0.0-20210529063254-f4c35e4016d9/state.go:2018 +0x277
panic(0x5683a0, 0xc0000160d8)
 /usr/local/go/src/runtime/panic.go:965 +0x1b9
github.com/yuin/gopher-lua.(*LState).where(0xc0001b4000, 0x0, 0x1, 0x40376b, 0xc0004becc0)
 /home/fuzz/go/pkg/mod/github.com/yuin/gopher-lua@v0.0.0-20210529063254-f4c35e4016d9/state.go:735 +0x27e
github.com/yuin/gopher-lua.(*LState).raiseError(0xc0001b4000, 0x1, 0x579c16, 0x11, 0x0, 0x0, 0x0)
 /home/fuzz/go/pkg/mod/github.com/yuin/gopher-lua@v0.0.0-20210529063254-f4c35e4016d9/state.go:689 +0x1b7
github.com/yuin/gopher-lua.(*LState).RaiseError(...)
 /home/fuzz/go/pkg/mod/github.com/yuin/gopher-lua@v0.0.0-20210529063254-f4c35e4016d9/state.go:1671
github.com/yuin/gopher-lua.(*LState).registryOverflow(0xc0001b4000)
 /home/fuzz/go/pkg/mod/github.com/yuin/gopher-lua@v0.0.0-20210529063254-f4c35e4016d9/state.go:1666 +0x5a
github.com/yuin/gopher-lua.(*registry).resize(0xc0001b20a0, 0x1401)
 /home/fuzz/go/pkg/mod/github.com/yuin/gopher-lua@v0.0.0-20210529063254-f4c35e4016d9/state.go:394 +0x102
github.com/yuin/gopher-lua.(*registry).SetTop(0xc0001b20a0, 0x1401)
 /home/fuzz/go/pkg/mod/github.com/yuin/gopher-lua@v0.0.0-20210529063254-f4c35e4016d9/state.go:411 +0xf5
github.com/yuin/gopher-lua.init.3.func27(0xc0001b4000, 0xc080000000, 0xc0001b6000, 0x0)
 /home/fuzz/go/pkg/mod/github.com/yuin/gopher-lua@v0.0.0-20210529063254-f4c35e4016d9/vm.go:997 +0x7d7
github.com/yuin/gopher-lua.mainLoop(0xc0001b4000, 0xc0001b6000)
 /home/fuzz/go/pkg/mod/github.com/yuin/gopher-lua@v0.0.0-20210529063254-f4c35e4016d9/vm.go:31 +0xea
github.com/yuin/gopher-lua.(*LState).callR(0xc0001b4000, 0x0, 0xffffffffffffffff, 0x0)
 /home/fuzz/go/pkg/mod/github.com/yuin/gopher-lua@v0.0.0-20210529063254-f4c35e4016d9/state.go:1211 +0x256
github.com/yuin/gopher-lua.(*LState).Call(...)
 /home/fuzz/go/pkg/mod/github.com/yuin/gopher-lua@v0.0.0-20210529063254-f4c35e4016d9/state.go:1967
github.com/yuin/gopher-lua.(*LState).PCall(0xc0001b4000, 0x0, 0xffffffffffffffff, 0x0, 0x5b00d8, 0xc0001e6380)
 /home/fuzz/go/pkg/mod/github.com/yuin/gopher-lua@v0.0.0-20210529063254-f4c35e4016d9/state.go:2030 +0x114
github.com/yuin/gopher-lua.(*LState).DoString(0xc0001b4000, 0x57d180, 0x1e, 0xc0001b4000, 0xc000050778)
 /home/fuzz/go/pkg/mod/github.com/yuin/gopher-lua@v0.0.0-20210529063254-f4c35e4016d9/auxlib.go:405 +0xbd
main.main()
 /home/fuzz/fuzz-go/deneme.go:14 +0x7e
exit status 2
```

### Additional contract requirements

- For Lua’s `select` function, valid negative integer indices count from the end of the extra arguments; for example, `-1` selects the final extra argument and `-2` selects from the second-to-last extra argument onward.
