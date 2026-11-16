Decoder overrides defaults with null values
**Is your feature request related to a problem? Please describe.**

The decoder overrides the default values of a nested struct with zero-initialised value.

```go
package main

import (
	"fmt"
	//"gopkg.in/yaml.v3"
	"strings"
	"github.com/goccy/go-yaml"
)

type Default struct {
	Key string `yaml:"key"`
}

type Test struct {
	First    string  `yaml:"first"`
	Defaults Default `yaml:"second"`
}

func main() {
	yml := `
first: "Test"
second:
  # Just want to document the fields of the nested struct
#  key: "Value from YAML"
`

	test := Test{Defaults: Default{Key: "My default Value"}}
	d := yaml.NewDecoder(strings.NewReader(yml))
	if err := d.Decode(&test); err != nil {
		fmt.Println("cannot decode: ", err)
		return
	}

	fmt.Printf("%#v", test)
}
```

This prints with **go-yaml** `main.Test{First:"Test", Defaults:main.Default{Key:""}}`  while with..
**yaml.v3** it prints `main.Test{First:"Test", Defaults:main.Default{Key:"My default Value"}}`.

**Describe the solution you'd like**

It might be desirable to stick with the current behaviour by default (as it might break some applications that depend on it, I guess!), however, it would be nice if there would be an option to control this, something like `yaml.IgnoreNullValues()`.

### Additional contract requirements

- When a nested struct field already holds a value and the YAML for that field is null (the key has no value, is `null`, or is `~`), decoding leaves that struct's existing field values unchanged.
- When the YAML for a nested struct field is a mapping that only sets some of its keys, the keys it sets are decoded and the remaining fields keep their existing values.
- No decoder option is required for either behaviour above.
