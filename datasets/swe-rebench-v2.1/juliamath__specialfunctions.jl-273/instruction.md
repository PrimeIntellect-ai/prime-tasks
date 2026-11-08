expint: spurious domainerror for negative order
This doesn't seem right, since the result is actually real:
```jl
julia> expint(-9.4, 12.2)
ERROR: DomainError with 12.2:
En will only return a complex result if called with a complex argument
Stacktrace:
 [1] expint(::Float64, ::Float64, ::Int64) at /Users/stevenj/.julia/dev/SpecialFunctions/src/expint.jl:373
 [2] expint(::Float64, ::Float64) at /Users/stevenj/.julia/dev/SpecialFunctions/src/expint.jl:363
 [3] top-level scope at REPL[26]:1

julia> expint(-9.4, 12.2+0im)
1.1967544495848934e-6 + 0.0im
```
cc @augustt198

### Additional contract requirements

- For real inputs, `expint(-2, -2.2)` must return a value approximately equal to `-2.0680909972407264331884989` with relative tolerance `1e-14`.
