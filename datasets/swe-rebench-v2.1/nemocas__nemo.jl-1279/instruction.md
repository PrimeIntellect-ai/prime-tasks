`root(a::fmpq, b::Int) -> fmpq` is missing

### Additional contract requirements

- Add a public method `root(x::fmpq, n::Int; check::Bool=true)` that returns the exact `n`-th root of `x` as an `fmpq`.
- The exponent `n` must be positive. A `DomainError` is thrown when `n <= 0`, and also when `x < 0` and `n` is even (with the default `check=true`).
