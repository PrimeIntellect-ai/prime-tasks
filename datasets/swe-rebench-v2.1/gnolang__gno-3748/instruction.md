gnovm: missing line number and column number in errors from Go2Gno
If we look at this gno code
```go
// https://github.com/gnolang/gno/issues/3727

package main

func () A()

func main() {}
```

Running it results in
```shell
tests/files/parse_err0.gno:0: method has no receiver (code=2)
```

but really it should be

```shell
tests/files/parse_err0.gno:5:1: method has no receiver (code=2)
```
