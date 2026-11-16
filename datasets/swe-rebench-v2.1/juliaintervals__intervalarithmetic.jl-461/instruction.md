Inconsistent errors when constructing intervals with NaN bound
The error raised when trying to create an interval with one `NaN` bound is change depending on the constructor used:

```julia
julia> NaN..1
ERROR: InexactError: Int64(NaN)
Stacktrace:
 [1] Type at .\float.jl:703 [inlined]
 [2] rationalize(::Type{Int64}, ::Float64, ::Float64) at .\rational.jl:134
 [3] #rationalize#150 at .\rational.jl:189 [inlined]
 [4] rationalize at .\rational.jl:189 [inlined]
 [5] #rationalize#151 at .\rational.jl:190 [inlined]
 [6] rationalize at .\rational.jl:190 [inlined]
 [7] atomic(::Type{Interval{Float64}}, ::Float64) at C:\Users\Kolaru\.julia\dev\IntervalArithmetic\src\intervals\conversion.jl:107
 [8] ..(::Float64, ::Int64) at C:\Users\Kolaru\.julia\dev\IntervalArithmetic\src\intervals\intervals.jl:136
 [9] top-level scope at none:0

julia> @interval(NaN, 1)
ERROR: InexactError: Int64(NaN)
Stacktrace:
 [1] Type at .\float.jl:703 [inlined]
 [2] rationalize(::Type{Int64}, ::Float64, ::Float64) at .\rational.jl:134
 [3] #rationalize#150 at .\rational.jl:189 [inlined]
 [4] rationalize at .\rational.jl:189 [inlined]
 [5] #rationalize#151 at .\rational.jl:190 [inlined]
 [6] rationalize at .\rational.jl:190 [inlined]
 [7] atomic(::Type{Interval{Float64}}, ::Float64) at C:\Users\Kolaru\.julia\dev\IntervalArithmetic\src\intervals\conversion.jl:107
 [8] top-level scope at none:0

julia> interval(NaN, 1)
ERROR: ArgumentError: `[NaN, 1]` is not a valid interval. Need `a ≤ b` to construct `interval(a, b)`.
Stacktrace:
 [1] interval(::Float64, ::Int64) at C:\Users\Kolaru\.julia\dev\IntervalArithmetic\src\intervals\intervals.jl:103
 [2] top-level scope at none:0
```

All three should probably return the same `ArgumentError` (that could be specialized on the `NaN` case).

### Additional contract requirements

For a NaN-containing pair, the `interval(a, b)` function and the `a..b` operator must reject the bounds by returning the empty interval and warning. The `@interval(a, b)` form must not produce an interval containing NaN; because it evaluates endpoint expressions differently, rejection by an exception is also acceptable, and no particular exception type is required. A common `ArgumentError` is not required.
