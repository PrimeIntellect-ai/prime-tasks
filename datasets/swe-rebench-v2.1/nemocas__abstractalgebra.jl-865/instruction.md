polcoeff and pol_length not defined for absolute series
The documentation doesn't mention that these functions are currently only available for relative series.

Currently the absolute series generic code uses coeff and length instead of polcoeff and pol_length.

It would perhaps be better to define polcoeff and pol_length for absolute series too so the interface is more similar or to document the difference.

It might also make sense to rename polcoeff to pol_coeff.

### Additional contract requirements

- Define `polcoeff(a::AbsSeries, n::Int)` for absolute series. It returns the coefficient at zero-based index `n`, throws `DomainError` when `n` is negative, and returns zero in the base ring when `n` is at or beyond the stored length.
- Define `pol_length(x::AbstractAlgebra.AbsSeriesElem)` for absolute series; it returns the same stored-coefficient count as `length(x)`.
