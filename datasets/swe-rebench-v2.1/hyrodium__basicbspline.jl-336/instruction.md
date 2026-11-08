missing constructor `BSplineSpace`
```julia
julia> using BasicBSpline

julia> BSplineSpace{3}(knotvector"111111111111")
BSplineSpace{3, Int64, KnotVector{Int64}}(KnotVector([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]))

julia> BSplineSpace{3, Int64, KnotVector{Int64}}(KnotVector([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]))
ERROR: MethodError: no method matching BSplineSpace{3, Int64, KnotVector{Int64}}(::KnotVector{Int64})

Closest candidates are:
  BSplineSpace{p, T, K}(::BSplineSpace{p, T} where T<:Real) where {p, T, K}
```
