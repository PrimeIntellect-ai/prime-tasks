`InexactError` with `fittingcontrolpoints`
```julia
julia> P = BSplineSpace{3}(KnotVector(1:12))
BSplineSpace{3, Int64}(KnotVector([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]))

julia> BasicBSpline.innerproduct_R(x->x, (P,))
ERROR: InexactError: Int64(0.17499999999999996)
Stacktrace:
 [1] Int64
   @ ./float.jl:812 [inlined]
 [2] convert
   @ ./number.jl:7 [inlined]
 [3] setindex!
   @ ./array.jl:903 [inlined]
 [4] innerproduct_I(func::var"#3#4", Ps::Tuple{BSplineSpace{3, Int64}})
   @ BasicBSpline ~/.julia/dev/BasicBSpline/src/_Fitting.jl:95
 [5] innerproduct_R(func::var"#3#4", Ps::Tuple{BSplineSpace{3, Int64}})
   @ BasicBSpline ~/.julia/dev/BasicBSpline/src/_Fitting.jl:200
 [6] top-level scope
   @ REPL[12]:1
```
