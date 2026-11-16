Multilin case statements should be allowed
It's not possible to break cases into multiple lines but it really should!

```go
switch {
case true, // Does work for *first* statement.
	false:
	fmt.Println("x")
case true, // Doesn't work here
	false:
	fmt.Println("x")
case true || // Same with || operator
	false:
	fmt.Println("x")
case true, false: // Ok
	fmt.Println("x")
case true || false: // Ok
	fmt.Println("x")
}

```
