UTF-8 Byte Order Marks causes parser errors
When a .proto file starts with the UTF-8 byte order marks, protoparse returns an unexpected syntax error:

```
foo:1:1: syntax error: unexpected $unk
```

This snippet reproduces the error:
```go
package main

import (
	"bytes"
	"fmt"
	"io"
	"io/ioutil"

	"github.com/jhump/protoreflect/desc/protoparse"
)

func main() {
	file := append([]byte{0xEF, 0xBB, 0xBF}, []byte(`syntax = "proto3";`)...)
	parser := &protoparse.Parser{
		Accessor: func(_ string) (closer io.ReadCloser, e error) {
			return ioutil.NopCloser(bytes.NewReader(file)), nil
		},
	}

	_, err := parser.ParseFiles("foo")
	if err != nil {
		fmt.Println("Error!", err)
		return
	}
	fmt.Println("Success!")
}
```
Note the UTF-8 BOM at the start of the otherwise valid proto3 file. This used to work, and seems to have been introduced sometime after https://github.com/jhump/protoreflect/commit/9a9113f80b5726d48e1a25b035161cc5c46714c1, as that was the commit present in `buf` 0.18.0, which successfully parsed this.
