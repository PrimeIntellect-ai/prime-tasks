`Unmarshal` fails when decoding `null` as string
`Unmarshal` fails when decoding `null` as string.
Referring to `encoding/json`, the expected result is an empty string.

## Reproduction code

https://play.golang.org/p/-mRPc-XSadc

```go
package main

import (
	"fmt"

	"github.com/goccy/go-json"
)

type Message struct {
	Field string `json:"field"`
}

func main() {
	ok := `{"field": "value"}`
	ng := `{"field": null}`

	for _, s := range []string{ok, ng} {
		var msg Message
		err := json.Unmarshal([]byte(s), &msg)
		if err != nil {
			panic(err) // panics for `ng`
		}
		fmt.Println(msg)
	}
}
```
