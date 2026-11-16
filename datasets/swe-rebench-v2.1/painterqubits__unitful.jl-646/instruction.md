delegate all comparison methods
As pointed out in https://github.com/JuliaIntervals/IntervalArithmetic.jl/issues/237#issuecomment-728384934

the assumption at https://github.com/PainterQubits/Unitful.jl/blob/47d131be92eefae1b49cd02b0a9f9a55b74be97f/src/quantities.jl#L324


```julia
[HIDDEN]
```

might not hold. Take for instance

```julia
using IntervalArithmetic: IntervalArithmetic, interval
using Unitful: Unitful, m

a = interval(0, 0)
b = interval(0, 1)
@assert a <= b
@assert a*m <= b*m  # assertion failure here
```

and the reason why is:

```julia
julia> a <= b
true

julia> a < b
false

julia> a == b
false
```

It seems worthwhile to [HIDDEN]

### Additional contract requirements

- For unitful quantities, `<=` must honor the underlying values’ less-than-or-equal semantics, rather than infer the result from `<` and `==`. In particular, if the underlying values satisfy `a <= b` while both `a < b` and `a == b` are false, the corresponding unitful comparison must still return `true`.
