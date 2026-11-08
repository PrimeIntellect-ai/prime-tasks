panic - Mixed type array gives panic on export
```Go
package main

import (
	"fmt"
	"github.com/robertkrimen/otto"
)

func main() {

	vm := otto.New()

	_, err := vm.Run(`
var output = [[1,2.1], [3, 4]];
	`)

	if err != nil {
		fmt.Println(err)
		return
	}

	outputValue, err := vm.Get("output")
	if err != nil {
		fmt.Println(err)
		return
	}

	outputInterface, _ := outputValue.Export()

	fmt.Println(outputInterface)
}
```

Panic:

> panic: reflect.Set: value of type []interface {} is not assignable to type []int64
>
> goroutine 1 [running]:
> reflect.Value.assignTo(0x671a80, 0xc0420fd8c0, 0x97, 0x6bedd6, 0xb, 0x671a00, 0x0, 0x0, 0x671a80, 0xc0420fd8c0)
> 	C:/app/Go/src/reflect/value.go:2181 +0x30e
> reflect.Value.Set(0x671a00, 0xc0420efda0, 0x197, 0x671a80, 0xc0420fd8c0, 0x97)
> 	C:/app/Go/src/reflect/value.go:1351 +0xab
> vendor/github.com/robertkrimen/otto.Value.export(0x5, 0x6b4020, 0xc0420f9aa0, 0x0, 0x0)
> 	C:/Users/username/Documents/Eclipse/src/vendor/github.com/robertkrimen/otto/value.go:718 +0xe9f
> vendor/github.com/robertkrimen/otto.Value.Export(0x5, 0x6b4020, 0xc0420f9aa0, 0x0, 0x0, 0x0, 0x0)
> 	C:/Users/username/Documents/Eclipse/src/vendor/github.com/robertkrimen/otto/value.go:648 +0x6e
> main.main()
> 	C:/Users/username/Documents/Eclipse/src/test/main.go:27 +0x344
>
