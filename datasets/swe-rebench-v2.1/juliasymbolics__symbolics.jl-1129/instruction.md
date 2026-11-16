Array function registration doesn't overload promote types correctly
MWE:
```julia
using Symbolics
@register_array_symbolic bar(x::AbstractVector, p::AbstractMatrix) begin
    size = size(x)
    eltype = promote_type(eltype(x), eltype(p))
end
@variables x[1:3] p[1:3, 1:3];
ex = bar(x, p)
ex2 = similarterm(Symbolics.unwrap(ex), bar, [Symbolics.unwrap(x), Symbolics.unwrap(p)]; metadata=Symbolics.metadata(ex))
typeof(ex2)
```
outputs
```julia
julia> typeof(ex2)
SymbolicUtils.BasicSymbolic{Any}
```

### Additional contract requirements

For the registered `bar` example from the MWE, reconstructing its array term must retain an informative symbolic array type with `Real` elements rather than defaulting to `BasicSymbolic{Any}`. For the registered `ggg` example, the call produces a two-dimensional symmetric symbolic array of `Real` elements. A reconstructed `ggg` term must retain an informative symbolic type that is a subtype of `AbstractArray{Real}`, rather than defaulting to `BasicSymbolic{Any}`. These requirements concern the resulting symbolic types and array behavior; they do not prescribe a particular type-promotion query.
