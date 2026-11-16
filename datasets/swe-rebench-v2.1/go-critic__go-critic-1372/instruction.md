Consider ignoring some common methods in hugeParam checker
For example, `String() string` method sometimes is defined on the value to make it possible to pass it as `%s` value.

```
package main

import "fmt"

type examplePtr struct{}

func (*examplePtr) String() string { return "PTR" }

type exampleValue struct{}

func (exampleValue) String() string { return "VALUE" }

func main() {
	ptr1 := examplePtr{}
	ptr2 := &examplePtr{}
	val1 := exampleValue{}
	val2 := &exampleValue{}
	fmt.Printf("%s %s %s %s\n", ptr1, ptr2, val1, val2)
}
```
https://go.dev/play/p/s7MxcI4YVWX
For ptr receiver, `ptr1` will not produce `PTR` string.
