`time-equal` garbled message when time returned from function
**Describe the bug**
The `time-equal` rule passes an `ast.Expr` to a `%s` placeholder in its message format, but not all `ast.Expr` implement `String()`, so junk is output for certain kinds of expressions (such as comparing a `time.Time` that's returned from a function call).

**To Reproduce**
Steps to reproduce the behavior:
1. I updated revive `go install github.com/mgechev/revive@latest`
2. I run it with the following flags & configuration file:

```shell
revive -config revive.toml time-equal-test.go
```

```toml
# config file
ignoreGeneratedHeader = false
severity = "warning"
confidence = 0.0
errorCode = 0
warningCode = 0

[rule.time-equal]
```

Source file `time-equal-test.go`:

```go
package test

import "time"

func isNow(t time.Time) bool { return t == time.Now() }

```

**Expected behavior**
Something more readable than:

```
time-equal-test.go:5:39: use t.Equal(&{%!s(*ast.SelectorExpr=&{0xc00007e7a0 0xc00007e7c0}) %!s(token.Pos=81) [] %!s(token.Pos=0) %!s(token.Pos=82)}) instead of "==" operator
```

### Additional contract requirements

- For `t == time.Now()`, the diagnostic must include `use t.Equal(time.Now()) instead of "==" operator`. For `time.Now() != t`, it must include `use !time.Now().Equal(t) instead of "!=" operator`.
