abs2 incorrectly defined for Taylor{Complex{T}}
Hi, I stumbled over this issue, when using TaylorSeries with complex numbers:

```julia
using TaylorSeries
t = Taylor1(Float64, 5)
abs2(t*im)
```
yields `- ( 1.0 - 0.0im ) t² + 𝒪(t⁶)`.

I think `abs2` is incorrectly defined for a complex type [here](https://github.com/JuliaDiff/TaylorSeries.jl/blob/dfb3f159def4fee8fbcbee29f8626c9c0bcac4be/src/other_functions.jl#L92).

Would it make sense to add the following definition?

```julia
[HIDDEN]
```
