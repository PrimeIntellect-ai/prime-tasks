bug on inline array reading
https://play.golang.org/p/l3cZy3n9T62

```
package main

import (
	"fmt"
	"github.com/goccy/go-yaml"
	y "gopkg.in/yaml.v2"
)

func main() {
	yml := `
- a: [2 , 2]
  b: [2 , 2]
  c: [2 , 2]`
	var d interface{}
	yaml.Unmarshal([]byte(yml), &d)
	fmt.Printf("%v\n%v\n", yml, d)
	y.Unmarshal([]byte(yml), &d)
	fmt.Printf("%v\n%v\n", yml, d)
}
- a: [2 , 2]
  b: [2 , 2]
  c: [2 , 2]
[map[a:[2 2]]]

- a: [2 , 2]
  b: [2 , 2]
  c: [2 , 2]
[map[a:[2 2] b:[2 2] c:[2 2]]]
```

### Additional contract requirements

- Unmarshalling the reported YAML must retain entries `a`, `b`, and `c` with their inline array values `[2, 2]`, including when trailing tabs follow the first two array lines.
