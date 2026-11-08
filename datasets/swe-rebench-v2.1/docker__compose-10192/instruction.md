[BUG] goroutine leak in `init()` of `v2/cmd/formatter` ?
### Description

Trying to build something that depends on `github.com/docker/compose/v2`, then ran into this issue, because all of our tests checks for goroutine leaks at the end of running.

### Steps To Reproduce

Run following test


```go
package main

import (
	"testing"

	_ "github.com/docker/compose/v2/cmd/formatter"
	"go.uber.org/goleak"
)

func TestLeak(t *testing.T) {
	defer goleak.VerifyNone(t)
}
```

Output:


```shell
$ go test
--- FAIL: TestLeak (0.45s)
    main_test.go:12: found unexpected goroutines:
        [Goroutine 19 in state chan send, with github.com/docker/compose/v2/cmd/formatter.init.0.func1 on top of the stack:
        goroutine 19 [chan send]:
        github.com/docker/compose/v2/cmd/formatter.init.0.func1()
                /home/wxh/go/pkg/mod/github.com/docker/compose/v2@v2.14.2/cmd/formatter/colors.go:120 +0x1de
        created by github.com/docker/compose/v2/cmd/formatter.init.0
                /home/wxh/go/pkg/mod/github.com/docker/compose/v2@v2.14.2/cmd/formatter/colors.go:104 +0x8b
        ]
FAIL
exit status 1
FAIL    tt      0.451s
```


This is because there is a non-terminating goroutine in the `init()`:

```go
	go func() {
		i := 0
		rainbow := []colorFunc{
			colors["cyan"],
			colors["yellow"],
			colors["green"],
			colors["magenta"],
			colors["blue"],
			colors["intense_cyan"],
			colors["intense_yellow"],
			colors["intense_green"],
			colors["intense_magenta"],
			colors["intense_blue"],
		}

		for {
			loop <- rainbow[i]
			i = (i + 1) % len(rainbow)
		}
	}()
```

### Workaround

Not a best practice to bypass questionable func, but...

```go
	defer goleak.VerifyNone(t, goleak.IgnoreTopFunction("github.com/docker/compose/v2/cmd/formatter.init.0.func1"))
```

### Compose Version

```Text
https://github.com/docker/compose/blob/v2.14.2/cmd/formatter/colors.go
```


### Docker Environment

_No response_

### Anything else?

_No response_
