DiscreteNonParametric == throws error
```
julia> DiscreteNonParametric(1:2) === DiscreteNonParametric(1:3)
ERROR: DimensionMismatch("arrays could not be broadcast to a common size; got a dimension with lengths 2 and 3")
```

The root cause is the broadcasting on possibly different length arrays [here](https://github.com/JuliaStats/Distributions.jl/blob/20c91d9efcc5f96913bf8e38be2e3fb14b21942b/src/univariate/discrete/discretenonparametric.jl#L63). Should be an easy fix, [HIDDEN] I can make a pull request if desired.

### Additional contract requirements

- The intended comparison is value equality (`==`), not identity (`===`). Comparing two `DiscreteNonParametric` distributions with supports of different lengths must return `false` rather than throw a dimension-mismatch error; correspondingly, `!=` must return `true`.
