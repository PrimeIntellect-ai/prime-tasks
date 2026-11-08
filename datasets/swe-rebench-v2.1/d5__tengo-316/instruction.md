Function re-assignment in another function causes SIGSEGV in Tengo VM
The following Tengo code:

```golang
func1 := func(a, b) {
    return a * b
}

func2 := func() {
    test := test(1, 2)
}

func2()
```

While completely bonkers (re-assigning a function), produces a SIGSEGV, which should not happen.

```text
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x28 pc=0x52eb39]

goroutine 1 [running]:
github.com/d5/tengo/v2.(*VM).run(0xc000180000)
	/home/runner/work/tengo/tengo/vm.go:542 +0x2ac9
github.com/d5/tengo/v2.(*VM).Run(0xc000180000, 0xc000180000, 0x400)
	/home/runner/work/tengo/tengo/vm.go:77 +0xcf
main.CompileAndRun(0xc0001026f0, 0xc000152000, 0x5e, 0x25e, 0xc0001163d0, 0xc, 0x0, 0xc000104120)
	/home/runner/work/tengo/tengo/cmd/tengo/main.go:144 +0x1d0
main.main()
	/home/runner/work/tengo/tengo/cmd/tengo/main.go:83 +0x420
```

I stumbled upon this by happenstance as a result of a typo in my code.

### Additional contract requirements

The fix must also satisfy the following observable behaviours, which are graded:

1. A local variable referenced on the right-hand side of its own `:=`
   definition, before it has been assigned, must not resolve to that local
   variable. The program

   ```golang
   (func() {
       fn := fn()
   })()
   ```

   must fail at compile time, and the compile error message must contain
   `unresolved reference 'fn`.

2. When a global variable and a new local variable in a function share a name,
   and the local variable's initializer calls that name, the right-hand-side
   reference must resolve to the outer (global) variable. The program

   ```golang
   f := func() { return 2 }
   out = (func() {
       f := f()
       return f
   })()
   ```

   must compile and run, and `out` must equal `2`.
