Validate error if blocks
Hi, I have the following issue while using the wsl tool

When two "if" blocks are together, I get: "if statements should only be cuddled with assignments"

```
func validateErr(err error) {
	if err == nil {
         ...
	}
	if errors.Is(err, ErrSomething) {
         ...
	}
...
}
```

But if I insert a space between them, i get : "if statements that check an error must be cuddled with the statement that assigned the error"

```
func validateErr(err error) {
	if err == nil {
         ...
	}

	if errors.Is(err, ErrSomething) {
         ...
	}
...
}
```
