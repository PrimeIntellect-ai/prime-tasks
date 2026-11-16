equality `==` for `BSplineSpace` is not defined
```julia
julia> P1 = BSplineSpace{2}(KnotVector(1,2))
BSplineSpace{2, Float64}(KnotVector([1.0, 2.0]))

julia> P2 = BSplineSpace{2}(KnotVector(1,2))
BSplineSpace{2, Float64}(KnotVector([1.0, 2.0]))

julia> P1 == P2
false
```
