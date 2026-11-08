confusing-naming FP on methods of generic types
**Describe the bug**
The `confusing-naming` check misfires on similarly named methods of distinct generic types.

**To Reproduce**
Steps to reproduce the behavior:
1. I updated revive `go install github.com/mgechev/revive@latest`
2. I run it with the following flags & configuration file:

```
revive -config revive.toml test.go
```

revive.toml:

```toml
[rule.confusing-naming]
```

test.go:

```go
package test

type x[T any] struct{}

func (x[T]) method() {
}

type y[T any] struct{}

func (y[T]) method() {
}
```

It's completely legitimate to define methods by the same name on different types.

The false positive only happens when both `x` and `y` are generic. Defining one or both as a concrete type (such as `type x struct{}`) makes the issue disappear.

**Expected behavior**
No `confusing-naming` issue is reported.

**Logs**
```
test.go:10:13: Method 'method' differs only by capitalization to function 'method' in the same source file
```

**Desktop (please complete the following information):**
 - OS: Ubuntu 23.04
 - `go version go1.20.6 linux/amd64`
