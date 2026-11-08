Exception when subtracting an Int64 scalar from a Interval{Rational{Int64}}
I encountered an exception while trying to subtract an Int64 integer from a Interval{Rational{Int64}} rational interval. REPL output below:
```julia
julia> using IntervalArithmetic

julia> x_0 = interval(1 // 3, 2 // 5)
[1//3, 2//5]

julia> x_0 - 1
ERROR: MethodError: no method matching atomic(::Type{Interval{Rational{Int64}}}, ::Interval{Rational{Int64}})
Closest candidates are:
  atomic(::Type{Interval{T}}, ::Interval) where T<:AbstractFloat at /home/user/.julia/packages/IntervalArithmetic/aGHTY/src/intervals/conversion.jl:122
  atomic(::Type{Interval{T}}, ::S) where {T<:AbstractFloat, S<:Real} at /home/user/.julia/packages/IntervalArithmetic/aGHTY/src/intervals/conversion.jl:95
  atomic(::Type{Interval{Rational{Int64}}}, ::Irrational) at /home/user/.julia/packages/IntervalArithmetic/aGHTY/src/intervals/conversion.jl:132
  ...
Stacktrace:
 [1] convert(::Type{Interval{Rational{Int64}}}, ::Interval{Rational{Int64}}) at /home/user/.julia/packages/IntervalArithmetic/aGHTY/src/intervals/conversion.jl:20
 [2] _promote at ./promotion.jl:259 [inlined]
 [3] promote at ./promotion.jl:282 [inlined]
 [4] -(::Interval{Rational{Int64}}, ::Int64) at ./promotion.jl:313
 [5] top-level scope at REPL[7]:1
```

I am on IntervalArithmetic v0.16.7. This occurred both on Julia 1.1.1 and on 1.5.1.
