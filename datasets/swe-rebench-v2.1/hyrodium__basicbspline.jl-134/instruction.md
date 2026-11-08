Fix type promotion in `bsplinebasis`
```julia
julia> k = KnotVector{Int}(1:12)
KnotVector([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])

julia> P = BSplineSpace{3}(k)
BSplineSpace{3, Int64}(KnotVector([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]))

julia> bsplinebasis(P,1,1)
ERROR: InexactError: Int64(-0.5)
Stacktrace:
 [1] Int64
   @ ./float.jl:812 [inlined]
 [2] _d
   @ ~/.julia/dev/BasicBSpline/src/_BSplineBasis.jl:3 [inlined]
 [3] macro expansion
   @ ~/.julia/dev/BasicBSpline/src/_BSplineBasis.jl:110 [inlined]
 [4] bsplinebasis(P::BSplineSpace{3, Int64}, i::Int64, t::Int64)
   @ BasicBSpline ~/.julia/dev/BasicBSpline/src/_BSplineBasis.jl:110
 [5] top-level scope
   @ REPL[11]:1

```

### Additional contract requirements

- For `k = KnotVector{Int}(1:12)`, `Pp = BSplineSpace{p}(k)` for `p = 0, 1, 2`, and `t = 5`, `bsplinebasis`, `bsplinebasis₊₀`, and `bsplinebasis₋₀` must return a `Float64`, both for `Pp` and for `BSplineDerivativeSpace{r}(Pp)` with `r = 0, 1, 2`. In those same cases, the values returned by `bsplinebasisall` must have element type `Float64`.
