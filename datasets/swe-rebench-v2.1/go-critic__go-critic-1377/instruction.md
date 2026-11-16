unlambda: false positive
```go
func New(options ...string) error {
	return nil
}

var NewWithTimeout = func(options ...string) error {
	return New(append(options, "timeout")...)
}
```

```
unlambda: replace `func(options ...string) error {
        return New(append(options, "timeout")...)
}` with `New` (gocritic)
var NewWithTimeout = func(options ...string) error {
                     ^

```
