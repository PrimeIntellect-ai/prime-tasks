Invalid "duplicate key" panic for non-constant literal composite
The following valid Go program panics with gno:

```go
package main

import "fmt"

func main() {
    x := 1
    a := map[int]int{x: 10, 1 * x: 20} // x and 1*x denote the same key
    fmt.Println(a)
}
```

With go:

```console
$ go run sample.go
map[1:20]
```

With gno:

```console
$ gnu run sample.go
panic running expression main(): duplicate key %!s(<nil>) in map literal
[...]
```

The panic would be correct if `x` was declared as constant: `const x = 1`, but not if x is a variable. In this case the map value for key `1` should be re-assigned.

The issue occurs for all key types which admit a constant value. The problem is that the expression processing of the key does not distinguish between a constant and a variable expression.
