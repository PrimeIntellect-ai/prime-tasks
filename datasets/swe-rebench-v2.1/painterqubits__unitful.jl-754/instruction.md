`uconvert` does not preserve the floating-point precision of quantities in some cases
MWE:
```julia
julia> using Unitful

julia> x = 100f0u"cm"
100.0f0 cm

julia> uconvert(u"m", x)
1.0f0 m

julia> x = 45f0u"°"
45.0f0°

julia> uconvert(u"rad", x)
0.7853981633974483 rad
```
@sostock, is this expected?
