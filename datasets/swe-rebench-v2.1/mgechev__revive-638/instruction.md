range-val-in-closure: incorrectly flags struct key if the key has the same name as a range variable
```go
package main

type t struct {
	key string
}

func main() {
	m := map[string]string{
		"a": "b",
	}

	for key := range m {
		myKey := key
		go func() {
			println(t{key: myKey})
		}()
	}
}
```

```
junk.go:15:14: range-val-in-closure: loop variable key captured by func literal (revive)
			println(t{key: myKey})
```
