defer FP on return statement in a function literal passed to the deferred function
**Describe the bug**
The `defer` check misfires on a `return` statement inside a function literal passed to the deferred function.

**To Reproduce**
Steps to reproduce the behavior:
1. I updated revive `go install github.com/mgechev/revive@latest`
2. I run it with the following flags & configuration file:

```shell
revive -config revive.toml test.go
```

revive.toml:
```toml
[rule.defer]
```

test.go:
```go
package test

func verify(fn func() error) {
	if err := fn(); err != nil {
		panic(err)
	}
}

func f() {
	defer verify(func() error {
		return nil
	})
}
```

Here, `verify` executes the given function and verifies that it has succeeded. We use this pattern in our project, and I don't see anything wrong with it.

Although `return` has no effect in a deferred function, this one is not in the deferrede function; it's in a function that's passed as an argument to the deferred function.

**Expected behavior**
No `defer` issue is reported.

**Logs**
```
test.go:11:3: return in a defer function has no effect
```

**Desktop (please complete the following information):**
 - Ubuntu 23.04
 - `go version go1.20.6 linux/amd64`
