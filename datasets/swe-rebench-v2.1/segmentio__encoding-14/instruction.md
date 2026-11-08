Marshalling fails with Interface members when they are nil
I was migrating some marshalling code to use this library over the standard library (thank you for making it!) and encountered this error. Note that the stdlib reports a nil error with data, while `segmentio/encoding/json` returns an error. i

Minimal repro:
```go
package main

import (
	"fmt"

	"github.com/segmentio/encoding/json"
)

type segmentJSON struct {
	Stringer fmt.Stringer
	Field    int `json:"MyInt"`
}

func main() {
	fmt.Println("segment-error")
	js := segmentJSON{Field: 2}
	fmt.Println(json.Marshal(js))
}
```

Output when using `encoding/json`:
```bash
❯ go run main.go
segment-error
[123 34 83 116 114 105 110 103 101 114 34 58 110 117 108 108 44 34 77 121 73 110 116 34 58 50 125] <nil>
```

with `github.com/segmentio/encoding/json`:
```
❯ go run main.go
segment-error
[] json: unsupported type: fmt.Stringer
```
