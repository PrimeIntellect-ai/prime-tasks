PDMat constructor fails for cholesky of a diagonal matrix
A minimal example:

```julia
using PDMats, LinearAlgebra
x = rand(10, 10)
PDMat(cholesky(Diagonal(x'x)))
```

<details>
  <summary>Stacktrace</summary>

```julia
ERROR: MethodError: Cannot `convert` an object of type Matrix{Float64} to an object of type Diagonal{Float64, Vector{Float64}}
Closest candidates are:
  convert(::Type{var"#s832"} where var"#s832"<:Diagonal, ::Union{LinearAlgebra.AbstractTriangular, Bidiagonal, Diagonal, SymTridiagonal, Tridiagonal}) at /buildworker/worker/package_linux64/build/usr/share/julia/stdlib/v1.6/LinearAlgebra/src/special.jl:53
  convert(::Type{T}, ::Factorization) where T<:AbstractArray at /buildworker/worker/package_linux64/build/usr/share/julia/stdlib/v1.6/LinearAlgebra/src/factorization.jl:58
  convert(::Type{T}, ::T) where T<:AbstractArray at abstractarray.jl:14
  ...
Stacktrace:
 [1] PDMat(mat::Matrix{Float64}, chol::Cholesky{Float64, Diagonal{Float64, Vector{Float64}}})
   @ PDMats ~/.config/julia/packages/PDMats/G0Prn/src/pdmat.jl:16
 [2] PDMat(fac::Cholesky{Float64, Diagonal{Float64, Vector{Float64}}})
   @ PDMats ~/.config/julia/packages/PDMats/G0Prn/src/pdmat.jl:21
 [3] top-level scope
   @ REPL[2]:1
```

</details>

Due to attempting to convert a `Matrix` to a `Diagonal`: https://github.com/JuliaStats/PDMats.jl/blob/213c37a2a94e7d14c21b54b2eeded4cb76270488/src/pdmat.jl#L16
