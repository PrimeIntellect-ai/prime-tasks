panic on Run with no selected nodes
If there's an application with no nodes selected, instead of returning an error, `Context.Run` panics.
Reproduction:

```go
func TestRegression(t *testing.T) {
        var emptyCLI struct{}
        parser, err := kong.New(&emptyCLI)
        assert.NoError(t, err)

        kctx, err := parser.Parse([]string{})
        assert.NoError(t, err)

        err = kctx.Run()
        assert.Error(t, err)
        assert.Contains(t, err.Error(), "no command selected")
}
```

This test passes against v1.2.1 but not against 1.6.0.
`git bisect` indicates that the issue was introduced in 2544d3f00855f6857cf121ce04608296b5858e4a.
