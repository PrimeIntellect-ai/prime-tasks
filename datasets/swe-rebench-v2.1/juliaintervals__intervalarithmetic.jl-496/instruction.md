Fixing broadcast requires changing eltype
```jl
julia> interval(0, 1) .* rand(2, 2)
ERROR: MethodError: no method matching Float64(::Interval{Float64})
Closest candidates are:
  Float64(::Real, ::RoundingMode) where T<:AbstractFloat at rounding.jl:200
  Float64(::T) where T<:Number at boot.jl:716
  Float64(::Irrational{:ℯ}) at irrationals.jl:189
```

[HIDDEN]

cc @krish8484

### Additional contract requirements

For an interval whose bounds have type `T`, `eltype` of the interval value returns `Interval{T}`. Broadcasting multiplication between an interval and an array succeeds and produces interval-valued entries.
