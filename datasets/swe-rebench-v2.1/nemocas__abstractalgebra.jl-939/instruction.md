Implement iroot
Currently Julia has isqrt for the integer floor of the square root of an integer. We propose adding iroot to both AbstractAlgebra and Nemo to give the floor of the integer root of its input, as we are going to make root raise an exception if the root is not exact.

### Additional contract requirements

This task concerns the `AbstractAlgebra` module only; the Nemo part of the base text is out of scope here.

The rounding rule for `iroot` is the round-toward-zero rule below, which governs wherever the base text says "floor". For example, for a negative odd exponent the result is rounded toward zero, so `iroot(-40, 3)` is `-3`, not `-4`.

Add the following public functions to the `AbstractAlgebra` module:

- `root(a::BigInt, n::Int; check::Bool=true)` and `root(a::T, n::Int; check::Bool=true) where T <: Integer`: return the integer `n`-th root of `a` as a value of the same type as `a`. When `check=true` (the default), throw an `ErrorException` if `a` is not a perfect `n`-th power; when `check=false`, return the truncated integer root without requiring exactness. Throw a `DomainError` when `n <= 0` or when `a < 0` and `n` is even.
- `iroot(a::BigInt, n::Int)` and `iroot(a::T, n::Int) where T <: Integer`: return the truncated integer part of the `n`-th root of `a` (round toward zero) as a value of the same type as `a`. Throw a `DomainError` when `n <= 0` or when `a < 0` and `n` is even.
- `ispower(a::T, n::Int) where T <: Integer`: return `true` if `a` is a perfect `n`-th power (there is an integer `b` with `a == b^n`) and `false` otherwise. Throw a `DomainError` when `n <= 0`.
- `ispower_with_root(a::T, n::Int) where T <: Integer`: return a tuple `(flag, q)`; when `a` is a perfect `n`-th power, `flag` is `true` and `q` is the integer `n`-th root of `a`; otherwise `flag` is `false` and `q` is zero. Throw a `DomainError` when `n <= 0`.
