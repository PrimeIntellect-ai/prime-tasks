Parsing multi-line values
I need to parse YAML files in a way that gives me a line number of each element. I started by using go-yaml/yaml for this but quickly realised that it's difficult to get accurate position information from it as it never gives me the raw original value from the file, only decoded value, which makes it difficult to tell how many lines is given value occupying.
I found this project, which seems great fit for it, and after poking around the API docs I think I figure out how to use it for it, but when I try to parse some multi-line with `parser.ParseBytes()` I see that some values span across multiple `DocumentNode`.

Here's an example: https://play.golang.org/p/5_bGwq7Md_H

```
package main

import (
	"fmt"

	"github.com/goccy/go-yaml/parser"
)

func main() {
	content := `
- key1: val
  key2:
    (
      foo
      +
      bar
    )
`
	f, err := parser.ParseBytes([]byte(content), parser.ParseComments)
	if err != nil {
		panic(err)
	}

	for _, doc := range f.Docs {
		fmt.Printf("doc: [%s]\n", doc.Body)
	}
}
```

Gives me 2 `DocumentNode` instances, once for `( foo + bar` and one for trailing `)`.
Am I doing something wrong here or is it a bug?
