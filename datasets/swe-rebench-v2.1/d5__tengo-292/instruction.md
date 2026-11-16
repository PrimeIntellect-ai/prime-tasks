panic: interface conversion: tengo.Object is *tengo.CompiledFunction, not *tengo.String
Having two source modules where the one uses the others gives panic.
```
package main

import (
	"fmt"

	"github.com/d5/tengo/v2"
	"github.com/d5/tengo/v2/stdlib"
)

func main() {

	script := tengo.NewScript([]byte(`
		module_a := import("module_a")
		module_b := import("module_b")
		module_b()
	`))
	mods := stdlib.GetModuleMap("json", "fmt", "math", "times")

	mods.AddSourceModule("module_a", []byte(`
		fubar := func(arr, low, n) {
		    i := low + 1
		    for i < n + 1 {
		    }
		}

		module_a := {
		    "fo": func(){}
		}

		export module_a
	`))

	mods.AddSourceModule("module_b", []byte(
		`export func(){
			module_a := import("module_a")
		}
	`))
	script.SetImports(mods)

	compiledFunc, err := script.Compile()
	if err != nil {
		panic(err)
	}

	fmt.Println("RUN")
	err = compiledFunc.Run()
	if err != nil {
		panic(err)
	}
}
```
