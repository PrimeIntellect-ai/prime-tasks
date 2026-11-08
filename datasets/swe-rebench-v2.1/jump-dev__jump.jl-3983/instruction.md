Can't multiply a `Matrix{AffExpr}` by a `Matrix{ComplexF64}`
MWE:
```julia
using JuMP

a = randn(ComplexF64, 2, 2)
model = Model()
@variable(model, x[1:2, 1:2])
(1 * x) * a
```
The other order works (`a * (1 * x)`), so I suppose only the mirror method is missing.

### Additional contract requirements

- The public function `add_to_expression!(aff, other, coef)` accepts two affine expressions `aff` and `other` whose scalar coefficient types may differ, together with a numeric constant `coef`, and mutates `aff` in place so that it represents `aff + coef * other`.
- `add_to_expression!` returns the modified `aff`.
- `add_to_expression!` throws a `MethodError` when its arguments do not satisfy these type constraints.
