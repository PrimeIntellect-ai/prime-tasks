Request: treat min, max and clear as built-in functions
**Is your feature request related to a problem? Please describe.**

go 1.21 has introduced new functions `min`, `max` and `clear`.
https://go.dev/ref/spec#Go_1.21

Currently revive does not treat `min`, `max` and `clear` as built-in functions,
https://github.com/mgechev/revive/blob/master/rule/redefines-builtin-id.go#L18-L34
so it does not report `redefinition of the built-in function` error.

```golang
// Reproduce issue
package main

import "fmt"

func main() {
	min := 0
	fmt.Println(min)
}
```

```
❯ revive -set_exit_status ./...

❯ echo $?
0
```

**Describe the solution you'd like**

revive treats `min`, `max` and `clear` as built-in functions on go 1.21+,
and reports the following error:
```
main.go: redefinition of the built-in function min
```

**Describe alternatives you've considered**

There may be an option not to make changes in order to maintain backward compatibility.

**Additional context**

NA
