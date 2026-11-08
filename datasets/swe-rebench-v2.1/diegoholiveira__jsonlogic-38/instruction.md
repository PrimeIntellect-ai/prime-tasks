Error if var is missing from data
Hello,

I seem to hit a case where the library is returning an error when a property, that is in the "logic" but not in the "data". Below is an example program to reproduce the issue.

```go
package main

import (
	"bytes"
	"fmt"
	"os"
	"strings"

	"github.com/diegoholiveira/jsonlogic"
)

func main() {
	logic := strings.NewReader(`{"logic":{"and":[{"!":{"var":"var_not_in_data"}}]}}`)
	data := strings.NewReader(`{"some_key": "value"}`)

	var result bytes.Buffer
	err := jsonlogic.Apply(logic, data, &result)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	fmt.Println(result.String())
}
```

And here's the output:

```
interface conversion: interface {} is nil, not []interface {}

Process finished with exit code 1
```

If I add the `var_not_in_data` to the `data` object it evaluates the expression correctly.

Edit Note: It used to panic with version 2, it just returns the error now with v3
