InEpsilon has inconsistent results with expected or actual values of Inf
```go
func TestInEpsilon1(t *testing.T) {
	div := 0.0
	require.InEpsilon(t, 1, 1/div, 0.001)
}

func TestInEpsilon2(t *testing.T) {
	div := 0.0
	require.InEpsilon(t, 1/div, 1, 0.001)
}
```

```
> go test -v -run InEps | grep -E '(PASS|FAIL)'
--- FAIL: TestInEpsilon1 (0.00s)
--- PASS: TestInEpsilon2 (0.00s)
```

_Originally posted by @ybrustin-te in https://github.com/stretchr/testify/issues/918#issuecomment-2416889992_

Given the difference between two Inf values cannot be determined, those assertions should both fail.
