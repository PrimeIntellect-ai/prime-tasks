Add methods for `float`
```julia
julia> k = KnotVector{Int}([1,2,3])
KnotVector([1, 2, 3])

julia> typeof(k)
KnotVector{Int64}

julia> float(k)
ERROR: MethodError: no method matching AbstractFloat(::KnotVector{Int64})
Closest candidates are:
  (::Type{T})(::AbstractChar) where T<:Union{AbstractChar, Number} at ~/julia/julia-1.7.2/share/julia/base/char.jl:50
  (::Type{T})(::Base.TwicePrecision) where T<:Number at ~/julia/julia-1.7.2/share/julia/base/twiceprecision.jl:255
  (::Type{T})(::Complex) where T<:Real at ~/julia/julia-1.7.2/share/julia/base/complex.jl:44
  ...
Stacktrace:
 [1] float(x::KnotVector{Int64})
   @ Base ./float.jl:269
 [2] top-level scope
   @ REPL[6]:1
```
