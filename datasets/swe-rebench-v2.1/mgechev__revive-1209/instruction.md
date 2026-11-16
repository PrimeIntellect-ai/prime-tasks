Improve "exported" rule
Right now, exported rule will report this

```go
//nolint:lll // foo
func Whatever() {}
```

>Blah blah commented should be form like ...

It also reports this

```go
//go:embed foo.json
var foo string
```

Or anything that is a Go directive

I spotted it by working on this https://github.com/gofr-dev/gofr/pull/1411 and especially this code

```go
		// code before
}

//nolint:exhaustive // We just want to take care of slice and struct in this case.
func (c *Client) QueryWithCtx(ctx context.Context, dest any, stmt string, values ...any) error {

		// code after
```

https://github.com/gofr-dev/gofr/pull/1411/files#diff-5931c571fb913c21edcd5cd8b864b2fee691ebda14070081ad5765696b51646dR120-123

I had to add a comment for the method to make it works.

The problem occurs with golangci-lint by using EXC0014 only

It might be related to the fact exported already report a comment should be present for exported

But here, for me, suggesting "should be form" with a Go directive is a false positive

### Additional contract requirements

A directive comment does not count as documentation for an exported declaration. This covers Go directives such as `//go:embed ...` and `//go:generate ...`, and also `//nolint:...` directives. When an exported declaration has only a directive comment, or no comment at all, it is reported with the message `exported <kind> <name> should have comment or be unexported`, where `<kind>` is `var`, `const`, `function` or `method`, and `<name>` is the declaration name (for a method, the receiver type name followed by `.` and the method name).
