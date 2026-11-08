ctx.GetError should not return err if there's nil
**Describe the bug**

Here's sample code:

```go
func itReturnsNoError(t gobdd.StepTest, ctx context.Context) context.Context {
	res, err := ctx.GetError(statsErrKey{})
	if err != nil {
		t.Error(err)
	}
	if res != nil {
		t.Errorf("expected no error but %+v received", res)
	}

	return ctx
}
```

When I want to check if the `GetError` returns an error, sometimes I want to get `nil` from it. But, in such case the `GetError` will return the `err` as the second returned value. It should be `nil` as well.

### Additional contract requirements

- When the requested key exists in the context and its stored value is `nil`, `GetError` must return `(nil, nil)`. A missing key must still return a non-nil error.
