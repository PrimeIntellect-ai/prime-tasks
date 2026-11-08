`useless-break` flags necessary `break` in `case`
**Describe the bug**
`useless-break` flags a `break` statement within a `case`, followed by a label

**To Reproduce**
Steps to reproduce the behavior:
On version `v1.7.0` (8ece20b0789c517bd3a6742db0daa4dd5928146d)

```shell
revive --config revive.toml demo/...
```

```toml
[rule.useless-break]
Enabled = true
```

```go
// demo/main/main.go
package main

import "fmt"

func main() {
	switch 1 {
	case 1:
		fmt.Println("foo bar")
		if false { // Add code that jumps to the label so it compiles.
			goto SOME_LABEL
		}
		break
	SOME_LABEL:
		panic(nil)
	}
}
```

**Expected behavior**
No lint error, since the `break` prevents the control flow from entering `SOME_LABEL`.

**Logs**
`demo/main/main.go:12:3: useless break in case clause`

**Desktop (please complete the following information):**
 - OS: `openSUSE Leap 15.6`
 - `go1.24.1 linux/amd64`
