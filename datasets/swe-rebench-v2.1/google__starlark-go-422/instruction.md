panic from built-in function leaves Thread in a bad state
This is the test code:
https://go.dev/play/p/SZFzWgchzeZ
```golang
package main

import (
	"fmt"
	"log"

	"go.starlark.net/starlark"
)

func check(err error) {
	if err != nil {
		log.Fatal(err)
	}
}

func main() {
	t := &starlark.Thread{}
	sd := starlark.StringDict{
		"test": starlark.NewBuiltin("test", func(*starlark.Thread, *starlark.Builtin, starlark.Tuple, []starlark.Tuple) (starlark.Value, error) {
			panic("panic")
			// println("123")
			return starlark.None, nil
		}),
	}
	g, err := starlark.ExecFile(t, "", `
def mytest():
	test()
`, sd)
	check(err)
	g.Freeze()
	v := g["mytest"]

	calltest := func() {
		defer func() {
			if e := recover(); e != nil {
				fmt.Println("get panic", e)
			}
		}()
		_, err = starlark.Call(t, v, make(starlark.Tuple, 0), nil)
		if err != nil {
			println("get err:", err.Error())
		}
	}

	calltest()
	calltest()

}

```

The output I am expecting is:
```
get panic panic
get panic panic
```

But the output I get is：
```
get panic panic
get err: function mytest called recursively
```


When starlark is aborted by Builtin panic, calling starlark.Call again will get an error. I would like a way to have starlark revert to a usable state without renew a Thread
