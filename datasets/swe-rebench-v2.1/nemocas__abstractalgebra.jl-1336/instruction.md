Missing view method for matrices
```
julia> using AbstractAlgebra

julia> m = ZZ[1 2; 3 4]
[1   2]
[3   4]

julia> @view m[1:1, :]
[1   2]

julia> @view m[1, :]
ERROR: MethodError: no method matching view(::AbstractAlgebra.Generic.MatSpaceElem{BigInt}, ::Int64, ::Colon)

Closest candidates are:
  view(::AbstractArray{<:Any, N}, ::Any...) where {N, M}
   @ Base subarray.jl:174
  view(::MatElem{T}, ::Colon, ::Colon) where T<:Union{NCRingElem, RingElement}
   @ AbstractAlgebra ~/.julia/packages/AbstractAlgebra/ElVzc/src/Matrix.jl:415
  view(::MatElem{T}, ::UnitRange{Int64}, ::Colon) where T<:Union{NCRingElem, RingElement}
   @ AbstractAlgebra ~/.julia/packages/AbstractAlgebra/ElVzc/src/Matrix.jl:411
  ...

Stacktrace:
 [1] top-level scope
   @ REPL[4]:1
```
