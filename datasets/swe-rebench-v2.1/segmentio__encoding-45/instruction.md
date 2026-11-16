json.Unmarshaler difference: UnmarshalJSON([]byte("null")) skipped
Go 1.14.8 linux/amd64

v0.1.15 does not use my custom `UnmarshalJSON()` for `[]byte("null")`

[Documentation](https://golang.org/pkg/encoding/json/#Unmarshaler) says:
> By convention, to approximate the behavior of Unmarshal itself, Unmarshalers implement UnmarshalJSON([]byte("null")) as a no-op.

`encoding/json` calls it, `github.com/segmentio/encoding/json` skips it.

```
package main

import (
	//"encoding/json"
	"fmt"
	"github.com/segmentio/encoding/json"
)

type RawJsonString string

func (r *RawJsonString) UnmarshalJSON(b []byte) error {
	fmt.Printf("UnmarshalJSON: %s\n", string(b))
	if len(b) == 0 {
		*r = "null"
	} else {
		*r = RawJsonString(b)
	}
	return nil
}

func main() {
	var out RawJsonString
	if err := json.Unmarshal([]byte("null"), &out); err != nil {
		panic(err)
	}
	fmt.Printf("out = %#v\n", out)
}
```


`encoding/json`:
```
  UnmarshalJSON: null
  out = "null"
```

`github.com/segmentio/encoding/json`:
```
  out = ""
```
