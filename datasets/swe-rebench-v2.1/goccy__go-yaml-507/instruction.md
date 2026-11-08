Trailing new lines are added to literal strings
Even if they are not part of a literal string, trailing newlines are systematically added to the string

```yaml
foo: |
  bar


# ↑↑↑ Note the two newlines right after the literal string
```

In this siituation, the `bar` value will be `"bar\n\n"` instead of `"bar\n"`.

Note that this also applies with strip sign `|-`

Here is a simple reproduction case:

```golang
package main

import (
	"fmt"
	goYaml "github.com/goccy/go-yaml"
)

func main() {
	yml := `
foo: |-
  bar


`
	var vmap[string]any
	goYaml.Unmarshal([]byte(yml), &v)

	fmt.Println(v["foo"])
	// -> "bar\n\n"
}
```

And a related playground: https://go.dev/play/p/XG6oCnbwwiz

 - Go version: 1.21.2
 - go-yaml's Version: v1.11.2
