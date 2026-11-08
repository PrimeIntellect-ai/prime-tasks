convenience methods for arithmetics with vectors of `fmpz` and `fmpq`
Currently `fmpz[1, 2, 3] // 2` and `2 * fmpz[1, 2, 3]` work because of generic methods in `base/arraymath.jl` and `base/rational.jl`, respectively.
However, the "more natural" inputs `fmpz[1, 2, 3] // fmpz(2)` and `fmpz(2) * fmpz[1, 2, 3]` do not work.
The same applies to the situation where `fmpz` is replaced by `fmpq`.

I propose to add the following.
```julia
[HIDDEN]
```
Where would be the right place for the methods in question, perhaps `Nemo/src/flint/fmpz.jl` and `Nemo/src/flint/fmpq.jl`, respectively?

### Additional contract requirements

- For `Vector{fmpz}` and `fmpz`, `v // x` performs element-wise rational division and returns a `Vector{fmpq}`. For `Vector{fmpq}` and `fmpq`, `v // x` performs element-wise rational division and returns a `Vector{fmpq}`. Division by zero raises an error.
- For vectors of either type, multiplying by a scalar of the same type on either side produces a vector containing the corresponding element-wise products. The result has the same element type as the input vector.
