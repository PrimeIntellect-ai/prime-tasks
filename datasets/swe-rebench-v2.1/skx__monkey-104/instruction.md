Encountered a panic when attempting to retrieve an index value from a string
I encountered a panic when attempting to retrieve an index value from a string.

```
let i = "index";
puts(i["d"])
```

```
panic: interface conversion: object.Object is *object.String, not *object.Integer

goroutine 1 [running]:
github.com/skx/monkey/evaluator.evalStringIndexExpression(...)
        expr/staging/src/github.com/skx/monkey/evaluator/evaluator.go:1157
github.com/skx/monkey/evaluator.evalIndexExpression({0x113d918, 0xc000010048?}, {0x113d918?, 0xc000010060})
        expr/staging/src/github.com/skx/monkey/evaluator/evaluator.go:1126 +0x47f
github.com/skx/monkey/evaluator.EvalContext({0x113d800, 0x1227780}, {0x113d0b0?, 0xc000078080?}, 0xc00006e2d0)
        expr/staging/src/github.com/skx/monkey/evaluator/evaluator.go:184 +0x13fd
github.com/skx/monkey/evaluator.evalExpression({0x113d800, 0x1227780}, {0xc0000143d0?, 0x1, 0xc00006e2d0?}, 0x101480b?)
        expr/staging/src/github.com/skx/monkey/evaluator/evaluator.go:1000 +0xf2
github.com/skx/monkey/evaluator.EvalContext({0x113d800, 0x1227780}, {0x113cfe8?, 0xc00006a0a0?}, 0xc00006e2d0)
        expr/staging/src/github.com/skx/monkey/evaluator/evaluator.go:149 +0xe52
github.com/skx/monkey/evaluator.EvalContext({0x113d800, 0x1227780}, {0x113ccf0?, 0xc00006e3f0?}, 0xc00006e2d0)
        expr/staging/src/github.com/skx/monkey/evaluator/evaluator.go:55 +0x11b
github.com/skx/monkey/evaluator.evalProgram({0x113d800, 0x1227780}, 0x1?, 0x0?)
        expr/staging/src/github.com/skx/monkey/evaluator/evaluator.go:961 +0xac
github.com/skx/monkey/evaluator.EvalContext({0x113d800, 0x1227780}, {0x113cca0?, 0xc000010030?}, 0xc00006e2d0)
        expr/staging/src/github.com/skx/monkey/evaluator/evaluator.go:53 +0xba
github.com/skx/monkey/evaluator.Eval(...)
        expr/staging/src/github.com/skx/monkey/evaluator/evaluator.go:32
main.main()
        expr/main.go:24 +0x1bf
exit status 2

```

### Additional contract requirements

- For a string index that is not an integer, such as `"狐犬"["x"]`, evaluation must not panic; it must return either an Error object or an empty string.
- For the expression `"狐犬"[-3]`, evaluation must return an Error object or the empty string.
