Extend inclusion check for interval and interval box
```julia
julia> (0 .. 1) ⊆ IntervalBox(0 .. 1, 1)
ERROR: ArgumentError: [0, 1] ∈ [0, 1]¹ is not defined
Stacktrace:
 [1] in(X::IntervalArithmetic.Interval{Float64}, Y::IntervalBox{1, Float64})
   @ IntervalArithmetic ~/.julia/packages/IntervalArithmetic/997vH/src/multidim/intervalbox.jl:82
 [2] issubset(l::IntervalArithmetic.Interval{Float64}, r::IntervalBox{1, Float64})
   @ Base ./abstractset.jl:293
 [3] top-level scope
   @ REPL[39]:1
```
