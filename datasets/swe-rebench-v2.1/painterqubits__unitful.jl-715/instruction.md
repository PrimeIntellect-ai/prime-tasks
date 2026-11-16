Wrong result when broadcasting `ustrip` over ranges whose `eltype` and `step` have different units
```julia
julia> r = StepRange{typeof(1m),typeof(1cm)}(1m,1cm,2m)
(1//1:1//100:2//1) m

julia> length(r)
101

julia> ustrip.(r)
1:1:2

julia> length(ans)
2
```
