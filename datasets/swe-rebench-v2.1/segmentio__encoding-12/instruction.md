Different error message with encoding/json
Here is an example
json.go
```
package main

import (
	"encoding/json"
	"fmt"
	"math"
)

type A struct {
	B float64
}

func main() {
	c := A{
		B: math.NaN(),
	}
	_, err := json.Marshal(c)
	fmt.Println(err)
}
```

```
diff json.go json_segmentio.go
< 	"encoding/json"
---
> 	"github.com/segmentio/encoding/json"
```
The output of `json.go`:
```
json: unsupported value: NaN
```
The output of `json_segmentio.go`:
```
json: unsupported value: unsupported value
```
