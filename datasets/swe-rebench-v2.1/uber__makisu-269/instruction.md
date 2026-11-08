Panic on parsing malformed dockerfile
**Describe the bug**

I've been playing with [go-fuzz](https://github.com/dvyukov/go-fuzz) and have found a couple of crashes on parsing malformed dockerfile:

**To Reproduce**
1. `FROM ${0:+0}`:

```go
// +build ignore

package main

import (
	"github.com/uber/makisu/lib/parser/dockerfile"
)

func main() {
	data := "FROM ${0:+0}"

	dockerfile.ParseFile(data, map[string]string{})
}

```

fails with
```
panic: runtime error: index out of range [0] with length 0

goroutine 1 [running]:
github.com/uber/makisu/lib/parser/dockerfile.newFromDirective(0xc0000961e0, 0xc0000961b0, 0xc0000a608c, 0x4, 0xc00009a5b0, 0xc0000a6001)
	/Users/bayandin/go/src/github.com/uber/makisu/lib/parser/dockerfile/from.go:49 +0x30f
github.com/uber/makisu/lib/parser/dockerfile.newDirective(0xc0000a6080, 0xc, 0xc0000961b0, 0x1000, 0xc0000a6080, 0xc, 0xffffffffffffffff)
	/Users/bayandin/go/src/github.com/uber/makisu/lib/parser/dockerfile/directive.go:59 +0x1be
github.com/uber/makisu/lib/parser/dockerfile.ParseFile(0x114203d, 0xc, 0xc000096150, 0x0, 0x0, 0x0, 0x110de00, 0xc000016118)
	/Users/bayandin/go/src/github.com/uber/makisu/lib/parser/dockerfile/parse_file.go:42 +0x2b7
main.main()
	/Users/bayandin/go/src/github.com/uber/makisu/lib/parser/dockerfile/test.go:12 +0x44
exit status 2
```

2.
```dockerfile
FROM 0
COPY \
```

```go
// +build ignore

package main

import (
	"github.com/uber/makisu/lib/parser/dockerfile"
)

func main() {
	data := `FROM 0
COPY \ `

	dockerfile.ParseFile(data, map[string]string{})
}
```

fails with

```
panic: runtime error: index out of range [0] with length 0

goroutine 1 [running]:
github.com/uber/makisu/lib/parser/dockerfile.newCopyDirective(0xc0000723f0, 0xc000072330, 0xc00001a17c, 0x4, 0xc000013ab0, 0xc00001a101)
	/Users/bayandin/go/src/github.com/uber/makisu/lib/parser/dockerfile/copy.go:39 +0x6a3
github.com/uber/makisu/lib/parser/dockerfile.newDirective(0xc00001a174, 0x7, 0xc000072330, 0xff9, 0xc00001a174, 0x7, 0x0)
	/Users/bayandin/go/src/github.com/uber/makisu/lib/parser/dockerfile/directive.go:59 +0x1be
github.com/uber/makisu/lib/parser/dockerfile.ParseFile(0x1142511, 0xe, 0xc0000722d0, 0x0, 0x0, 0x0, 0x110de00, 0xc000016118)
	/Users/bayandin/go/src/github.com/uber/makisu/lib/parser/dockerfile/parse_file.go:42 +0x2b7
main.main()
	/Users/bayandin/go/src/github.com/uber/makisu/lib/parser/dockerfile/test.go:13 +0x44
exit status 2
```

**Expected behaviour**
A proper error message that dockerfile is malformed

**Additional context**
makisu version is 2be7a18
