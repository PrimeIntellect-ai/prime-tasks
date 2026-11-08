`⊊(::BSplineSpace, ::BSplineSpace)` is not supported
```julia
julia> using BasicBSpline

julia> P = BSplineSpace{1}(KnotVector(1:8))
BSplineSpace{1, Float64}(KnotVector([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]))

julia> P
BSplineSpace{1, Float64}(KnotVector([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]))

julia> P ⊆ P
true

julia> P ⊊ P
ERROR: MethodError: no method matching length(::BSplineSpace{1, Float64})
Closest candidates are:
  length(::Union{Base.KeySet, Base.ValueIterator}) at ~/julia/julia-1.7.1/share/julia/base/abstractdict.jl:58
  length(::Union{ArrayInterface.BidiagonalIndex, ArrayInterface.TridiagonalIndex, ArrayInterface.BandedBlockBandedMatrixIndex, ArrayInterface.BandedMatrixIndex, ArrayInterface.BlockBandedMatrixIndex}) at ~/.julia/packages/ArrayInterface/TCj9U/src/array_index.jl:209
  length(::Union{LinearAlgebra.Adjoint{T, <:Union{StaticArrays.StaticVector{<:Any, T}, StaticArrays.StaticMatrix{<:Any, <:Any, T}}}, LinearAlgebra.Diagonal{T, <:StaticArrays.StaticVector{<:Any, T}}, LinearAlgebra.Hermitian{T, <:StaticArrays.StaticMatrix{<:Any, <:Any, T}}, LinearAlgebra.LowerTriangular{T, <:StaticArrays.StaticMatrix{<:Any, <:Any, T}}, LinearAlgebra.Symmetric{T, <:StaticArrays.StaticMatrix{<:Any, <:Any, T}}, LinearAlgebra.Transpose{T, <:Union{StaticArrays.StaticVector{<:Any, T}, StaticArrays.StaticMatrix{<:Any, <:Any, T}}}, LinearAlgebra.UnitLowerTriangular{T, <:StaticArrays.StaticMatrix{<:Any, <:Any, T}}, LinearAlgebra.UnitUpperTriangular{T, <:StaticArrays.StaticMatrix{<:Any, <:Any, T}}, LinearAlgebra.UpperTriangular{T, <:StaticArrays.StaticMatrix{<:Any, <:Any, T}}, StaticArrays.StaticVector{<:Any, T}, StaticArrays.StaticMatrix{<:Any, <:Any, T}, StaticArrays.StaticArray{<:Tuple, T}} where T) at ~/.julia/dev/StaticArrays/src/abstractarray.jl:1
```

### Additional contract requirements

For B-spline spaces, `A ⊊ B` is true exactly when `A` is a subset of `B` and the two spaces differ. It is false when the spaces are equal or when `A` is not a subset of `B`. The non-strict comparison remains reflexive: `P ⊆ P` is true.
