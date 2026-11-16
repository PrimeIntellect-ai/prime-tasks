bug: validation of a slice of non-empty interface against an array schema should pass
### Context

An array schema validates only against a slice of empty interface: `[]interface{}{...}`. If a slice of non-empty interface (e.g. `[]string{...}`) is attempted to validate against that schema, this error occurs: `unhandled value of type []string`

### Reproduce

```go
package main

import (
	"fmt"

	"github.com/getkin/kin-openapi/openapi3"
)

func main() {
	schema := &openapi3.Schema{
		Type:        "array",
		UniqueItems: true,
		Items:       openapi3.NewStringSchema().NewRef(),
	}
	data := []string{"foo", "bar"}
	err := schema.VisitJSON(data)
	fmt.Println(err)
}
```

### Expected

In this case, a nil error should be printed because `VisitJSON` would recognize that `data` is a slice.

There is a bug in `VisitJSON` where the `[]interface{}` case does not cover all slices: https://github.com/getkin/kin-openapi/blob/9f99fee5a643dd7522772022cda4eee8b7f3f614/openapi3/schema.go#L1108-L1109

### Additional contract requirements

A slice recognized as an array value must have each element validated against the array schema's item schema. It must also obey the schema's `UniqueItems` constraint.
