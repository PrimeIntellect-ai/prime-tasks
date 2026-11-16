Add PanicAssertionFunc
There's already common function types for the following assertion groups:
* [`assert.BoolAssertionFunc`](https://pkg.go.dev/github.com/stretchr/testify/assert.BoolAssertionFunc)
* [`assert.ComparisonAssertionFunc`](https://pkg.go.dev/github.com/stretchr/testify/assert.ComparisonAssertionFunc)
* [`assert.ErrorAssertionFunc`](https://pkg.go.dev/github.com/stretchr/testify/assert.ErrorAssertionFunc)
* [`assert.ValueAssertionFunc`](https://pkg.go.dev/github.com/stretchr/testify/assert.ValueAssertionFunc)

These are very useful for doing table driven tests, but seems like there's no `PanicAssertionFunc`. It could look like this:
```
[HIDDEN]
```

### Additional contract requirements

- Add an exported `assert.PanicAssertionFunc` function type for using panic assertions as values in table-driven tests. Values of this type must be callable like `assert.Panics` and `assert.NotPanics`, accepting an `assert.TestingT`, an `assert.PanicTestFunc`, and optional variadic message arguments, and returning a boolean result.
