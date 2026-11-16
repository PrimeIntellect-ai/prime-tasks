`chol_lower` does not avoid allocations
https://github.com/JuliaStats/PDMats.jl/blob/dfcf96c90ade0ad6052855a3e4b3488b3dbe002a/src/chol.jl#L2 always has a superfluous copy, even though the point of defining `chol_lower` in this package is to avoid the extra allocation (as mentioned in the comment a few lines further down), to work around the issue that https://github.com/JuliaLang/julia/pull/42920 tries to address upstream.

MWE:
```julia
julia> using LinearAlgebra, PDMats

julia> A = rand(100, 100); C = A'A;

julia> PDMats.chol_lower(C); PDMats.chol_lower(cholesky(C)); cholesky(C).U';

julia> @allocated PDMats.chol_lower(C)
160240

julia> @allocated PDMats.chol_lower(cholesky(C))
80192

julia> @allocated cholesky(C).U'
80192
```

### Additional contract requirements

- `chol_lower(a)` for a dense square `Matrix` interprets `a` as Hermitian using its lower triangle and returns the lower-triangular Cholesky factor `L` of that Hermitian matrix, so that `L * L'` equals the Hermitian matrix defined by the lower triangle of `a`. The Hermitian matrix defined by the lower triangle is positive definite.
- `chol_lower(a)` for a `Cholesky` object returns the lower-triangular Cholesky factor of the factorized matrix.
- `chol_upper(a)` for a `Cholesky` object returns the upper-triangular Cholesky factor of the factorized matrix.
