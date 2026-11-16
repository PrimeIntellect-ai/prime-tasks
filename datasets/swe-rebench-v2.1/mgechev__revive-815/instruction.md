False positive on `for` loop
**Describe the bug**

`for` loops where the condition has side-effects and the block is empty can be valid.

**To Reproduce**

```
package main

import "fmt"

func main() {
	next := 0
	iter := func(v *int) bool {
		*v = next
		next++
		fmt.Println(*v)
		return next < 10
	}

	z := 0
	for iter(&z) {
	}
}
```

```
$ revive .
main.go:1:1: should have a package comment
main.go:15:15: this block is empty, you can remove it
```

Such code may be present in locations where you have an iterator interface and want to skip over rest-of the entries, but still read them.

**Expected behavior**

No warning.

**Desktop (please complete the following information):**
 - OS: Windows 11
 - go version go1.20.1 windows/amd64
