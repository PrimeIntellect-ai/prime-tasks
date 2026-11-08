Incorrect string representation of MappingNode in flow style
**Describe the bug**

The `String` representation of `MappingNode` in flow style is incorrect.

**To Reproduce**

1. Parse a yaml in map type into a `MappingNode`.
1. Set `SetIsFlowStyle` to true.
1. Call the `String` method of the node.

https://go.dev/play/p/yViy2dYoVUk

```yaml
volumes:
  name: config-volume
  configMap:
    name: app-config
```

```go
package main

import (
	"fmt"

	"github.com/goccy/go-yaml/ast"
	"github.com/goccy/go-yaml/parser"
)

func main() {
	a, err := parser.ParseFile("data.yaml", 0)
	if err != nil {
		panic(err)
	}
	d := a.Docs[0]
	n := d.Body.(*ast.MappingNode)
	n.SetIsFlowStyle(true)
	fmt.Println(n.String())
}
```

The actual output is:

```yaml
{volumes:
{name: config-volume, configMap:
{name: app-config}}}
```

**Expected behavior**

The output should be:

```yaml
{volumes: {name: config-volume, configMap: {name: app-config}}}
```

**Version Variables**
 - Go version: `go1.23.4 darwin/arm64`
 - go-yaml's Version: `1.15.15` (This is not a regression; I have tested with older versions as well)
