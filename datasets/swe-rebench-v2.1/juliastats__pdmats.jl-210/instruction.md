Stack overflow in `MvNormal(::Vector{Real}, UniformScaling{Float64}`
```julia
Status `~/test/Project.toml`
  [31c24e10] Distributions v0.25.113
  [37e2e46d] LinearAlgebra v1.11.0

julia> using LinearAlgebra: I

julia> using Distributions: MvNormal

julia> MvNormal(Float64[1.0, 2.0], 0.5 * I)
IsoNormal(
dim: 2
μ: [1.0, 2.0]
Σ: [0.5 0.0; 0.0 0.5]
)

julia> MvNormal(Real[1.0, 2.0], 0.5 * I)
ERROR: StackOverflowError:

```

This comes from here

https://github.com/JuliaStats/Distributions.jl/blob/3de6038ef9b041ceaf649bc324d60ca65fcf09eb/src/multivariate/mvnormal.jl#L190-L193

The underlying issue is that `convert(AbstractArray{Real}, ScalMat(2, 0.5)`, as defined in PDMats.jl https://github.com/JuliaStats/PDMats.jl/blob/592634b4dfadcf9ed74a6123ceff23c776bd93a1/src/scalmat.jl#L11 doesn't actually convert to Real.

```julia
julia> using PDMats: ScalMat

julia> sm = ScalMat(2, 0.5)
2×2 ScalMat{Float64}:
 0.5  0.0
 0.0  0.5

julia> convert(AbstractArray{Real}, sm)
2×2 ScalMat{Float64}:
 0.5  0.0
 0.0  0.5
```

I wasn't quite sure if this should be an upstream issue (i.e. whether this is intended behaviour on the part of PDMats.jl), because ScalMat only keeps a single number as the scale parameter and Julia doesn't convert scalars to `Real`. On the other hand one could specify the type parameter explicitly:

```julia
julia> MvNormal(Real[1.0, 2.0], ScalMat{Real}(2, 0.5))
MvNormal{Real, ScalMat{Real}, Vector{Real}}(
dim: 2
μ: Real[1.0, 2.0]
Σ: [0.5 0.0; 0.0 0.5]
)
```
