string-format rule not working on method called when obj is inside an struct.
**Describe the bug**
The string-format rule search only for function calls and methods, but if the object is
inside a structure, the method call is not found by the rule.
This is a typical pattern when we want a generic Logger interface and different implementations. In this case `Logger` is a port and `MyLogger` would be an adapter from a project with hexagonal architecture. This implementation is injected in main to a service.

**To Reproduce**
Steps to reproduce the behavior:
1. Create go file with the following code:
```golang
package main

import "fmt"

type Logger interface {
	Error(msg string, keysAndValues ...any)
}
type MyLogger struct {
}

func (m *MyLogger) Error(msg string, _ ...any) {
	fmt.Println(msg)
}

type Service struct {
	logger Logger
}

func main() {
	s := Service{
		logger: &MyLogger{},
	}
	s.logger.Error("Test")
}
```
2. I run it with the following flags & configuration file:

```shell
revive main.go
```

_config_
```toml
[rule.string-format]
  arguments = [
    ["logger.Error", "/^([^A-Z]|$)/",  "must not start with a capital letter"]]
```

**Expected behavior**
I spect it to fail with

`./tests/main.go:23:17: must not start with a capital letter`

as the logger.Error call start with a capital letter

**Desktop (please complete the following information):**
 - OS: Gentoo
 - Version of Go: 1.20

**Additional context**
MR is created with working solution (I don't know if the best)
