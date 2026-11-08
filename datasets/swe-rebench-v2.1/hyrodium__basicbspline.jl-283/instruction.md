`countknots` is sometimes incorrect
```julia
julia> using BasicBSpline

julia> k = KnotVector([-2,-1,-0.0,-0.0,0.0,1,3])
KnotVector([-2.0, -1.0, -0.0, -0.0, 0.0, 1.0, 3.0])

julia> countknots(k,0)
1

julia> countknots(k,-0.)
2
```
Both `countknots(k,0)` and `countknots(k,-0.)` should return `3`.
