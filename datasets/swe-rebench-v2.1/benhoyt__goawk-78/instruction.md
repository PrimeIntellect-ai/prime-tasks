Fix how we handle numstr type when setting $0 directly
For example, this script prints `1` under GoAWK, but under (g)awk it prints `0` (presumably the correct answer):

```
BEGIN { $0="0"; print !$0 }
```

There's a commented-out test for this in `interp/interp_test.go`:

```go
{`BEGIN { $0="0"; print !$0 }`, "", "0\n", "", ""},
```

### Additional contract requirements

- Also, `BEGIN { $1="10"; print($1<2) }` must print `1`.
