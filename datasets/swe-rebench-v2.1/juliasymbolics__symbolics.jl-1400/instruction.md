`NaNMath.pow` derivative throws `DomainError`
On the master branch:

```julia
julia> using Symbolics, ForwardDiff, NaNMath

julia> @variables x;

julia> ForwardDiff.derivative(y -> NaNMath.pow(x, y), 0.5)
NaNMath.pow(x, 0.5)*log(x)

julia> substitute(ForwardDiff.derivative(y -> NaNMath.pow(x, y), 0.5), x => -1.0)
ERROR: DomainError with -1.0:
...
```

### Additional contract requirements

- `ForwardDiff.derivative(z -> NaNMath.pow(x, z), 0.5)` must, after substituting a positive base `b`, have derivative value `b^0.5 ln(b)`. After substituting a negative base such as `-1.0`, its value must be `NaN` rather than raising a `DomainError`.
- `ForwardDiff.derivative(z -> x^z, 0.5)` must continue to raise a `DomainError` when a negative base with a non-integer exponent is substituted.
- When the base is zero and the exponent is positive, the derivative is zero.
