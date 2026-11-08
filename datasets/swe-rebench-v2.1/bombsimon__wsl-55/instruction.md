Not all blocks are parsed
Must be more generous about when to enter a block and parse it.

**Gives no error but should**

```go
var foo string

func() {
    var err error
    foo = "1"
}
```

**Gives error if assigned to variable**

```go
var foo string

x := func() {
    var err error
    foo = "1"
}
```

> assignments should only be cuddled with other assignments

Also this gives no error, assignign or not:

```go
var err error
foo, err = func() { return "", nil }
```
