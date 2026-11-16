need API to enumerate names/bindings of a Function's local variables
Hi all,

I am trying to access the context variable that calls the function in a custom built-in function, can I do it?

```go
var code = `
name = "hungtcs"
hello();
`

func main() {
  var predeclared = starlark.StringDict{
    "hello": starlark.NewBuiltin("hello", func(thread *starlark.Thread, fn *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
      // Question: How do I access global variables here?
      // fmt.Printf("hello %s\n", name)
      return starlark.None, nil
    }),
  }

  globals, err := starlark.ExecFile(
    &starlark.Thread{},
    "main.star",
    code,
    predeclared,
  )
  if err != nil {
    panic(err)
  }

  fmt.Printf("globals: %v\n", globals)
}
```

My idea was to implement code similar to the following, but using go to writing the `hello` method:

```python


def hello():
  print("hello %s" % name)
name = "hungtcs"
hello();
```

### Additional contract requirements

Add the following public API to package `go.starlark.net/starlark`:

- A public struct type `Binding` with exported fields `Name string` and `Pos syntax.Position`, where `syntax` is `go.starlark.net/syntax`. `Name` is the binding identifier's name, and `Pos` is the source position of the binding identifier (the location at which the variable is bound).
- The `DebugFrame` interface gains `NumLocals() int`, returning the number of local variables of the frame's function, and `Local(i int) (Binding, Value)`, returning the binding and current value of the i'th local variable. Local indices enumerate a function's parameters before its other local variables. The value of a local variable that has not yet been assigned is nil.
- The `*Function` type gains `NumFreeVars() int`, returning the number of free (cell) variables captured by the function, and `FreeVar(i int) (Binding, Value)`, returning the binding and current value of the i'th free variable.
