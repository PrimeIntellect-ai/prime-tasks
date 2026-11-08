Writing SPDX fails when a package has an originator object with an empty string as the originator
Minimal reproducer

```go
package main

import (
	"bytes"
	"fmt"

	spdx_json "github.com/spdx/tools-golang/json"
	"github.com/spdx/tools-golang/spdx"
	"github.com/spdx/tools-golang/spdx/v2/common"
	"github.com/spdx/tools-golang/spdx/v2/v2_3"
)

func main() {
	w := bytes.NewBuffer(nil)
	o := common.Originator{
		OriginatorType: "type",
	}
	p := v2_3.Package{
		PackageOriginator: &o,
	}
	s := spdx.Document{
		Packages: []*v2_3.Package{
			&p,
		},
	}
	err := spdx_json.Write(s, w)
	if err != nil {
		fmt.Printf("%s", err)
	}

	fmt.Printf("%s", w.Bytes())
}
```

Output:

```
json: error calling MarshalJSON for type *common.Originator: unexpected end of JSON input
```

### Additional contract requirements

When an Originator has a non-empty type but an empty entity, JSON serialization must return an error rather than succeed with empty output.
