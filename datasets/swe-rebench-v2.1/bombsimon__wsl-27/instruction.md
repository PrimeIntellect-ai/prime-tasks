False-positive "if statements should only be cuddled with assignments used in the if statement itself"
What exactly does this check want me to change, or is this a false-positive?

Repro:
```go
foo := bar.Baz(foobar)
if t, ok := data[foo]; ok {
  data["hello."+foo] = t
  delete(data, foo)
}
```
