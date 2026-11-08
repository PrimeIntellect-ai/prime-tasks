comment-spacings exceptions do not work if there's no colon after the exception
**Describe the bug**
Some projects like Kubebuilder have markers that do not follow the pattern `//name:`, example: `//+optional`. Due to https://github.com/mgechev/revive/blob/f88f60da20b2cdc9db2ad6ce5978da32531b0cda/rule/comment-spacings.go#L34 [HIDDEN] they don't work.

**To Reproduce**
Steps to reproduce the behavior:
1.  Write this config file:
```toml
[rule.comment-spacings]
  arguments = ["+optional"]
```

1. Write this test file:
```go
package main

import "fmt"

// example is an example struct
//+optional
type example struct {
	a int
}

func main() {
	a := example{a: 1}
	fmt.Println(a.a)
}
```

**Expected behavior**
I don't get an error

**Logs**
I get an error (logs from golangci-lint but the idea is the same):
```
comment-spacings: no space between comment delimiter and comment text (revive)
        //+optional
        ^
```

**Desktop (please complete the following information):**
 - OS: OpenSUSE Tumbleweed
 - Version of Go: 1.22

### Additional contract requirements

- When `+optional` is configured as an exception, the rule must not report a spacing diagnostic for `//+optional`.
