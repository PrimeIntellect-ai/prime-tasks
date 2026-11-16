Add more methods for value_type(::Type{<:AbstractJuMPScalar})
It would be great to have an interface to get the numerical type of a JuMP variable. That is, is if I do
```julia
using JuMP

model = GenericModel{Float32}()
@variable(model, x)
@variable(model, y in ComplexPlane())
```
to have a way to tell that `x` has `Float32` coefficients and `y` has `ComplexF32`.

I mean, I can do `typeof(x).parameters[1]`, but that's just asking for trouble.

A bit related, it would also be nice to have an interface to tell if a JuMP variable is real (which would follow from the above).
