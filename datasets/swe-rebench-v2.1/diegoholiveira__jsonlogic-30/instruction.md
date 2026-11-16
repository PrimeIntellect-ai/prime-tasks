0 divided by any number returning denominator instead of 0
Here is the sample program to reproduce

```
package main

import (
	"bytes"
	"fmt"
	"strings"
	"github.com/diegoholiveira/jsonlogic"
)

func main() {
	rule := `{"/":[0,10]}`
	logic := strings.NewReader(rule)
	data := strings.NewReader(`{}`)
	var result bytes.Buffer

	jsonlogic.Apply(logic, data, &result)

	fmt.Println(result.String())

}
```
