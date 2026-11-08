`copy(::KnotVector)` is not defined
```julia
julia> using BasicBSpline

julia> k = KnotVector(rand(5))
KnotVector([0.006113322971981083, 0.04390985165147909, 0.7172036901693241, 0.7285234235639948, 0.769119046562151])

julia> copy(k)
ERROR: MethodError: no method matching copy(::KnotVector{Float64})
Closest candidates are:
  copy(::LinearAlgebra.SymTridiagonal) at ~/julia/julia-1.8.0/share/julia/stdlib/v1.8/LinearAlgebra/src/tridiag.jl:159
  copy(::T) where T<:SHA.SHA1_CTX at ~/julia/julia-1.8.0/share/julia/stdlib/v1.8/SHA/src/types.jl:209
  copy(::Dict) at dict.jl:120
  ...
Stacktrace:
 [1] top-level scope
   @ REPL[18]:1
```

### Additional contract requirements

Calling `copy` on a `KnotVector` must succeed and produce an equivalent knot vector. Changes to the copied knot data must not change the original knot vector.
