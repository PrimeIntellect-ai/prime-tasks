Strange `issqsubset` behavior
I believe there were some issues like this before.
```julia
julia> using BasicBSpline

julia> P1 = BSplineSpace{3}(KnotVector([2, 2, 2, 3, 3, 4, 4, 4]))
BSplineSpace{3, Int64, KnotVector{Int64}}(KnotVector([2, 2, 2, 3, 3, 4, 4, 4]))

julia> P2 = BSplineSpace{3}(KnotVector([1, 3, 3, 3, 4]))
BSplineSpace{3, Int64, KnotVector{Int64}}(KnotVector([1, 3, 3, 3, 4]))

julia> dim(P1)
4

julia> dim(P2)
1

julia> P1 ⊑ P2  # shuold be false
true
```
