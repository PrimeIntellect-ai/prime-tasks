Coefficients of complex variables created with a GenericModel are always Float64
MWE:
```julia
using JuMP
model = GenericModel{Float32}()
@variable(model, x in ComplexPlane())
typeof(x)
typeof(Float32(1)*x)
```
In contrast, the real case works as expected:
```julia
using JuMP
model = GenericModel{Float32}()
@variable(model, x)
typeof(Float64(1)*x)
typeof(BigFloat(1)*x)
```

### Additional contract requirements

For a `GenericModel{T}`, complex variables created with `ComplexPlane()` and entries of Hermitian complex variables must use complex affine-expression coefficients parameterized by the model's coefficient type `T`. Multiplying a complex variable from that model by a scalar of type `T` must produce a compatible complex affine expression without coercing its complex coefficients to `Float64`.
