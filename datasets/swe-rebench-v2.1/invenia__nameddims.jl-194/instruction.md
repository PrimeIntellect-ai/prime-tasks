`deleteat!` not defined for NamedDimsVector
```julia
julia> deleteat!(NamedDimsArray{(:a, )}([1, 2, 3.]), 1)
ERROR: MethodError: no method matching deleteat!(::NamedDimsArray{(:a,), Float64, 1, Vector{Float64}}, ::Int64)
Closest candidates are:
  deleteat!(::Vector, ::Integer) at /Applications/Julia-1.7.app/Contents/Resources/julia/share/julia/base/array.jl:1421
  deleteat!(::Vector, ::Any) at /Applications/Julia-1.7.app/Contents/Resources/julia/share/julia/base/array.jl:1468
  deleteat!(::BitVector, ::Integer) at /Applications/Julia-1.7.app/Contents/Resources/julia/share/julia/base/bitarray.jl:949
  ...
Stacktrace:
 [1] top-level scope
   @ REPL[8]:1
```
related to https://github.com/mcabbott/AxisKeys.jl/issues/101
