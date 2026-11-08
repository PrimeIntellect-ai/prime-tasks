Make Delta* and Epsilon* funcs robust to NaN-Similarity
Currently the following funcs fail:

```golang
require.Delta(t, math.NaN(), math.NaN(), 1e-3)
require.Epsilon(t, math.NaN(), math.NaN(), 1e-3)
```

This makes comparing timeseries on similarity very tough.

Where I agree, that Equality checks on NaN-values should follow the Go-Spec and thus fail.
I disagree in the cases where we check for Similarity.

- A NaN-value is always semantically different to numerical values and thus a check like `NaN == NaN` should **fail** (see: [Issue #12025](https://github.com/golang/go/issues/12025#issuecomment-162643745)).
- In contrast: A NaN-value is not semantically much different to another NaN and thus a check like `NaN ≈ NaN` should **pass**.

Same logic applies to their `slice` and `map` derivatives.

Please have a look at #1081
