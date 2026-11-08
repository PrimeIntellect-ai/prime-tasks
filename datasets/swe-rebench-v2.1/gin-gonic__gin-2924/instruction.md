Incorrect TSR with mixed static and wildcard paths
The backtracking logic in #2897 is causing incorrect TSR values:
```go
func TestTreeBacktrackingTsr(t *testing.T) {
	tree := &node{}
	tree.addRoute("/api/:page/:name", fakeHandler("1"))
	tree.addRoute("/api/hello/:name/bar/", fakeHandler("1"))
	res := tree.getValue("/api/hello/x/bar", getParams(), getSkippedNodes(), false)
	if res.tsr != true {
		t.Fatalf("expected tsr")
	}
}
```
```
--- FAIL: TestTreeBacktrackingTsr (0.00s)
    tree_test.go:855: expected tsr
```

[HIDDEN]

### Additional contract requirements

- For the route registrations shown, looking up `/api/hello/x/bar` must set `tsr` to `true`.
- TSR results must be correct for lookups involving mixed static and wildcard route registrations, including when adding or removing a trailing slash would match a registered route.
