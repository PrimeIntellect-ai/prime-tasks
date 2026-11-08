Using error in Contains fails with confusing message
https://play.golang.org/p/u7Dfo4UnxZ0
```go
assert.Contains(t, "error string", errors.New("error"))
```
```
Error Trace:	prog.go:25
Error:      	"error string" does not contain "error"
Test:       	TestCaseA
```

Whereas this is what's needed to pass:
```diff
-assert.Contains(t, "error string", errors.New("error"))
+assert.Contains(t, "error string", errors.New("error").Error())
```

I would prefer if the failure message explained that it was an error type, otherwise it looks like a string does not contain another string: I've fallen foul to this in the past, and just spent 5-10mins again not realising that I needed to pass a `string` type as the 3rd argument.

It would be really nice to have the type printed here when the value isn't a `Stringer` =)

### Additional contract requirements

- The failure message for `Contains(t, "Hello World", errors.New("Hello"))` must include the exact text `"Hello World" does not contain &errors.errorString{s:"Hello"}`.
