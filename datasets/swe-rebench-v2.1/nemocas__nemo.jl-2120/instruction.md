Missing type promotion for Complex{Bool}
```
julia> ℂ = AcbField()
Complex Field with 256 bits of precision and error bounds

julia> z = ℂ(5+im)
5.00000000000000000000000000000000000000000000000000000000000000000000000000000 + 1.00000000000000000000000000000000000000000000000000000000000000000000000000000*im

julia> z*ℂ(im) #OK
-1.00000000000000000000000000000000000000000000000000000000000000000000000000000 + 5.00000000000000000000000000000000000000000000000000000000000000000000000000000*im

julia> z*im # Ka-boom
ERROR: MethodError: no method matching *(::AcbFieldElem, ::Complex{Bool})
The function `*` exists, but no method is defined for this combination of argument types.
```

### Additional contract requirements

For the Arb complex field element type `ComplexFieldElem` and the Acb field element type `AcbFieldElem`, the binary operations `+`, `-`, `*` and `//` must accept a native Julia `Complex{<:Real}` value in either operand position and return a field element of the same type as the field-element operand. In particular, multiplying a field element by `im` (a `Complex{Bool}`) must work.

The Arb and Acb complex field constructors must accept a native Julia `Complex{Int}` value, for example `CC(Complex{Int}(1))` and `CC(2 + 3im)`.
