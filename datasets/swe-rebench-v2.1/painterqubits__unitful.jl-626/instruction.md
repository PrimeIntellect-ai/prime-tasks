`floor` with degrees (`NoUnits`) and `digits` fails due to method ambiguity
MWE:

```julia
using Unitful: mm, °

x = 3.001mm
floor(typeof(x), x, digits=2) # works

a = 3.001°
floor(typeof(a), a, digits=2) # fails due to method ambiguity
```

Presumably because degrees are the `NoUnits` flavor.
This one is pretty opaque to me so I'm not sure where to begin for PR.

Perhaps related to #326?
In fact I suspect that if #328 were merged then I probably would just use `floor(a, digits=2)` for my use case (matching how non-unit values work), so it would be great to bump that one!

### Additional contract requirements

- `round(::Type{T}, x; kwargs...)`, where `T` is a concrete `Quantity` type and `x` is a dimensionless quantity (a quantity whose unit is `NoUnits`, such as degrees), returns the value of `x` rounded to the units of `T` as a quantity of type `T`. Keyword arguments such as `digits` are forwarded to the rounding.
- `round(::Type{T}, x, r::RoundingMode; kwargs...)` does the same, rounding according to the rounding mode `r`.
- `floor(::Type{T}, x; kwargs...)` works the same way for a dimensionless `x`.
- If `x` cannot be converted to the units of `T`, a `DimensionError` is raised.
