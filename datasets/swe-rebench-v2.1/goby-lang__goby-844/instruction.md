Including an Array causes an internal error
The following code causes an internal error and subsequent panic:

```ruby
» class TestClass
¤   include []
» end
interface conversion: vm.Object is *vm.RClass, not *vm.Error
#» UndefinedMethodError: Undefined Method '[]' for TestClass
» exit
interface conversion: vm.Object is nil, not *vm.Error
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x70 pc=0xa4b5b4]

goroutine 1 [running]:
github.com/goby-lang/goby/vm.(*VM).GetREPLResult(0xc420092820, 0xc4201fa540, 0x3)
  /path/to/go/src/github.com/goby-lang/goby/vm/repl.go:73 +0x44
github.com/goby-lang/goby/igb.StartIgb(0xbd6b78, 0x7)
  /path/to/go/src/github.com/goby-lang/goby/igb/repl.go:227 +0xd18
main.main()
  /path/to/go/src/github.com/goby-lang/goby/goby.go:29 +0xbaa
```

### Additional contract requirements

The `include` method must reject invalid arguments by returning an error object instead of causing an internal error or panic. The observable error messages are:

- `include []` and `include` (with no argument) return `ArgumentError: Expect 1 argument(s). got: 0`.
- `include "123"` (a non-module argument) returns `TypeError: Expect argument to be Module. got: String`.
