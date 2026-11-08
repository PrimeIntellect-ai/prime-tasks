Add support broadcasting `BSplineManifold`
```julia
julia> typeof(M)
BSplineManifold{1, (2,), Float64, Tuple{BSplineSpace{2, Float64}}}

julia> map.(sin,(0.5,0.55))
(0.479425538604203, 0.5226872289306592)

julia> map.(M,(0.5,0.55))
ERROR: MethodError: no method matching length(::BSplineManifold{1, (2,), Float64, Tuple{BSplineSpace{2, Float64}}})
Closest candidates are:
  length(::Union{Base.KeySet, Base.ValueIterator}) at ~/julia/julia-1.7.2/share/julia/base/abstractdict.jl:58
  length(::Union{LinearAlgebra.Adjoint{T, <:Union{StaticArrays.StaticVector{<:Any, T}, StaticArrays.StaticMatrix{<:Any, <:Any, T}}}, LinearAlgebra.Diagonal{T, <:StaticArrays.StaticVector{<:Any, T}}, LinearAlgebra.Hermitian{T, <:StaticArrays.StaticMatrix{<:Any, <:Any, T}}, LinearAlgebra.LowerTriangular{T, <:StaticArrays.StaticMatrix{<:Any, <:Any, T}}, LinearAlgebra.Symmetric{T, <:StaticArrays.StaticMatrix{<:Any, <:Any, T}}, LinearAlgebra.Transpose{T, <:Union{StaticArrays.StaticVector{<:Any, T}, StaticArrays.StaticMatrix{<:Any, <:Any, T}}}, LinearAlgebra.UnitLowerTriangular{T, <:StaticArrays.StaticMatrix{<:Any, <:Any, T}}, LinearAlgebra.UnitUpperTriangular{T, <:StaticArrays.StaticMatrix{<:Any, <:Any, T}}, LinearAlgebra.UpperTriangular{T, <:StaticArrays.StaticMatrix{<:Any, <:Any, T}}, StaticArrays.StaticVector{<:Any, T}, StaticArrays.StaticMatrix{<:Any, <:Any, T}, StaticArrays.StaticArray{<:Tuple, T}} where T) at ~/.julia/dev/StaticArrays/src/abstractarray.jl:1
  length(::Union{LinearAlgebra.Adjoint{T, S}, LinearAlgebra.Transpose{T, S}} where {T, S}) at ~/julia/julia-1.7.2/share/julia/stdlib/v1.7/LinearAlgebra/src/adjtrans.jl:171
  ...
Stacktrace:
 [1] _similar_shape(itr::BSplineManifold{1, (2,), Float64, Tuple{BSplineSpace{2, Float64}}}, #unused#::Base.HasLength)
   @ Base ./array.jl:600
 [2] _collect(cont::UnitRange{Int64}, itr::BSplineManifold{1, (2,), Float64, Tuple{BSplineSpace{2, Float64}}}, #unused#::Base.HasEltype, isz::Base.HasLength)
   @ Base ./array.jl:655
 [3] collect(itr::BSplineManifold{1, (2,), Float64, Tuple{BSplineSpace{2, Float64}}})
   @ Base ./array.jl:649
 [4] broadcastable(x::BSplineManifold{1, (2,), Float64, Tuple{BSplineSpace{2, Float64}}})
   @ Base.Broadcast ./broadcast.jl:704
 [5] broadcasted(::Function, ::BSplineManifold{1, (2,), Float64, Tuple{BSplineSpace{2, Float64}}}, ::Tuple{Float64, Float64})
   @ Base.Broadcast ./broadcast.jl:1300
 [6] top-level scope
   @ REPL[18]:1
```
