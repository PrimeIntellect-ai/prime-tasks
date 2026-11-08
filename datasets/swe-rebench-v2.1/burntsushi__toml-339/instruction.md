x = [] decodes into nil
The following program works differently between 0.3.1 and 0.4.1:

```
package main

import (
    "log"
    "reflect"

    "github.com/BurntSushi/toml"
)

func main() {
    blob := `
    x = []
    `
    var d map[string]interface{}
    if _, err := toml.Decode(blob, &d); err != nil {
        log.Fatal(err)
    }

    x := d["x"]
    log.Println(x, reflect.ValueOf(x).IsNil())
}
```

On 0.3.1,
```
[] false
```

On 0.4.1,
```
[] true
```

For my use case, this is a problem because I'm subsequently encoding the value into JSON and it writes `x = null` instead of the expected `x = []`. It also goes deeper than that, for instance `x = [[]]` would get JSONed as `x = [null]`.

Is this an intended change? Do you think it would be possible/correct to restore the previous behaviour?

### Additional contract requirements

When decoding a TOML array into interface-valued data, empty arrays nested within another array must also be represented as non-nil empty slices. For example, decoding `S = [[]]` must produce an outer slice containing a non-nil empty slice.
