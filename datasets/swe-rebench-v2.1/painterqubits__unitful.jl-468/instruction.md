`isapprox` for complex unitful arrays fails
MWE for v1.8.0:

```julia
using Unitful: mm
z = (1+im) * ones(2,3) * mm
isapprox(z, 2z)

ERROR: MethodError: no method matching isless(::ComplexF64, ::ComplexF64)
...
```

It works fine for a complex scalar `z = (1 + im) * mm`
This is perhaps slightly related to #310 but should be an easier case.
