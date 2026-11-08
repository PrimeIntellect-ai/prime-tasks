Too verbose error message when using Validate
This might be nitpicking, but a simple [program](https://go.dev/play/p/2oCBDlOgMmm):

```go
package main

import (
	"errors"

	"github.com/alecthomas/kong"
)

type Config struct{}

func (c Config) Validate() error {
	return errors.New("foobar")
}

func main() {
	var config Config
	kong.Parse(&config)
}
```

Outputs:

```
play: error: play: foobar
```

I find that double `play` in there ugly and unnecessary. Could it be removed?
