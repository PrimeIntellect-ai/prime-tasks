False positive with var-declaration
**Describe the bug**
The `var-declaration` check incorrectly warns if explicitly assigning a zero value in a `var` declaration, even if the zero value being assigned isn't the default for a variable of that type.

**To Reproduce**
Steps to reproduce the behavior:
1. I updated revive `go install github.com/mgechev/revive@latest`
2. I run it with the following flags:

```shell
revive main.go
```

main.go:

```go
// Package main is a package.
package main

func main() {
	var a any = 0
	_ = a

	var b any = ""
	_ = b
}
```

**Expected behavior**
I would expect no errors for `var-declaration`, because the zero value for a variable of type `any` is `nil`, not `0` or `""`.

**Logs**
```
main.go:5:14: should drop = 0 from declaration of var a; it is the zero value
main.go:8:14: should drop = "" from declaration of var b; it is the zero value
```

**Desktop (please complete the following information):**
 - OS: macOS 15.1.1
 - Version of Go: `go version go1.23.3 darwin/arm64`

**Additional context**
N/A
