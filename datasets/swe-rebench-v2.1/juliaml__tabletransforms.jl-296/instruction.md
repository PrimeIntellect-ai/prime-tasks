Revert of `CLR` assumes original data in `[0, 1]` range
We could show a warning to avoid silent bugs:

```julia
julia> t = [(a=10.,b=20.,c=70.)]
1-element Vector{@NamedTuple{a::Float64, b::Float64, c::Float64}}:
 (a = 10.0, b = 20.0, c = 70.0)

julia> n, c = apply(CLR(), t);

julia> revert(CLR(), n, c)
1-element Vector{@NamedTuple{a::Float64, b::Float64, c::Float64}}:
 (a = 0.09999999999999998, b = 0.19999999999999996, c = 0.7000000000000001)
```

or could rely on `Remainder` + `Closure` to pre-process the inputs.

### Additional contract requirements

- For CLR inputs whose original scale would otherwise be lost on reversion, do not silently return values at a different scale: either warn about the scale loss or preserve the scale so reversion restores the original values.
