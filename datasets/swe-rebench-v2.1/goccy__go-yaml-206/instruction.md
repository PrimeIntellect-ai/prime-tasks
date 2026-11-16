Single '{' at the beginning of strings w/o matching closing brace causes panic
I have the following code snippet:

```go
package main

import (
  "fmt"
  "github.com/goccy/go-yaml"
)

func main() {
  var result string
  err := yaml.Unmarshal([]byte("{this is invalid"), &result)
  if err != nil {
    fmt.Printf("Error: %v", err)
  }else{
    fmt.Printf("Got: %s", result)
  }
}
```

Playground: https://play.golang.org/p/9nZNkWEopY6

Obviously, I'm trying to unmarshal an invalid Yaml string (unmatched, leading curly brace).

**Expectation: A non-nil error is returned.**
**Actual Behaviour: A panic (nil-pointer dereference) is raised** (see log at the end of the post).

Interestingly, the string ```"{{this is invalid}"``` returns a non-nil error, as well as the string ```"this is{ invalid"```. The panic only seems to occur when the curly brace is at the beginning of the string and there are no other curly braces anywhere.

```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x38 pc=0x4e40ad]

goroutine 1 [running]:
github.com/goccy/go-yaml/parser.(*parser).createNullToken(...)
	/tmp/gopath386768941/pkg/mod/github.com/goccy/go-yaml@v1.8.2/parser/parser.go:132
github.com/goccy/go-yaml/parser.(*parser).parseMapValue(0xc000068c70, 0xc000060450, 0x556c60, 0xc00000c0a0, 0x0, 0x0, 0x10, 0x10, 0x513040)
	/tmp/gopath386768941/pkg/mod/github.com/goccy/go-yaml@v1.8.2/parser/parser.go:140 +0x42d
github.com/goccy/go-yaml/parser.(*parser).parseMappingValue(0xc000068c70, 0xc000060450, 0x0, 0x0, 0x0, 0x0)
	/tmp/gopath386768941/pkg/mod/github.com/goccy/go-yaml@v1.8.2/parser/parser.go:208 +0x1d4
github.com/goccy/go-yaml/parser.(*parser).parseMapping(0xc000068c70, 0xc000060450, 0xc00005c050, 0x0, 0x0, 0x0)
	/tmp/gopath386768941/pkg/mod/github.com/goccy/go-yaml@v1.8.2/parser/parser.go:30 +0x1e5
github.com/goccy/go-yaml/parser.(*parser).parseToken(0xc000068c70, 0xc000060450, 0xc00005c050, 0x0, 0xc000060450, 0xc000010280, 0x2)
	/tmp/gopath386768941/pkg/mod/github.com/goccy/go-yaml@v1.8.2/parser/parser.go:526 +0x1b5
github.com/goccy/go-yaml/parser.(*parser).parse(0xc000068c70, 0xc000010280, 0x2, 0x2, 0x0, 0x0, 0x1, 0x3)
	/tmp/gopath386768941/pkg/mod/github.com/goccy/go-yaml@v1.8.2/parser/parser.go:549 +0x105
github.com/goccy/go-yaml/parser.Parse(0xc000010280, 0x2, 0x2, 0x0, 0x2, 0xc000068cf8, 0x4ba637)
	/tmp/gopath386768941/pkg/mod/github.com/goccy/go-yaml@v1.8.2/parser/parser.go:585 +0x57
github.com/goccy/go-yaml/parser.ParseBytes(0xc000100000, 0x10, 0x40, 0x0, 0xc000060420, 0x10, 0x0)
	/tmp/gopath386768941/pkg/mod/github.com/goccy/go-yaml@v1.8.2/parser/parser.go:575 +0x8d
github.com/goccy/go-yaml.(*Decoder).parse(0xc00007e000, 0xc000100000, 0x10, 0x40, 0x0, 0x0, 0x0)
	/tmp/gopath386768941/pkg/mod/github.com/goccy/go-yaml@v1.8.2/decode.go:1291 +0x55
github.com/goccy/go-yaml.(*Decoder).decodeInit(0xc00007e000, 0x16, 0x16)
	/tmp/gopath386768941/pkg/mod/github.com/goccy/go-yaml@v1.8.2/decode.go:1319 +0xe9
github.com/goccy/go-yaml.(*Decoder).Decode(0xc00007e000, 0x5056e0, 0xc000010270, 0xc000068ee8, 0x4c6af2)
	/tmp/gopath386768941/pkg/mod/github.com/goccy/go-yaml@v1.8.2/decode.go:1361 +0x239
github.com/goccy/go-yaml.UnmarshalWithOptions(0xc00002c040, 0x10, 0x10, 0x5056e0, 0xc000010270, 0x0, 0x0, 0x0, 0x405d65, 0xc00005e058)
	/tmp/gopath386768941/pkg/mod/github.com/goccy/go-yaml@v1.8.2/yaml.go:161 +0x1a6
github.com/goccy/go-yaml.Unmarshal(...)
	/tmp/gopath386768941/pkg/mod/github.com/goccy/go-yaml@v1.8.2/yaml.go:154
main.main()
	/tmp/sandbox860830854/prog.go:10 +0xad
```
```

### Additional contract requirements

- For the input `{invalid`, the returned syntax error must have exactly this message:

```text
[1:2] unexpected map
>  1 | {invalid
        ^
```
