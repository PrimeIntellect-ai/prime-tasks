denominator error when converting fractional units
On Unitful 1.1.0,

```julia
julia> 1u"√m" |> u"√cm"
10.0 cm¹ᐟ²
```

After Unitful 1.2.0 with #323 (#319),

```julia
julia> 1u"√m" |> u"√cm"
ERROR: MethodError: no method matching denominator(::Float64)
Closest candidates are:
  denominator(::Integer) at rational.jl:232
  denominator(::Rational) at rational.jl:233
Stacktrace:
 [1] #s37#154 at /Users/tomyun/.julia/packages/Unitful/9XsxK/src/conversion.jl:41 [inlined]
 [2] #s37#154(::Any, ::Any, ::Any) at ./none:0
 [3] (::Core.GeneratedFunctionStub)(::Any, ::Vararg{Any,N} where N) at ./boot.jl:526
 [4] uconvert(::Unitful.FreeUnits{(cm¹ᐟ²,),𝐋¹ᐟ²,nothing}, ::Quantity{Int64,𝐋¹ᐟ²,Unitful.FreeUnits{(m¹ᐟ²,),𝐋¹ᐟ²,nothing}}) at /Users/tomyun/.julia/packages/Unitful/9XsxK/src/conversion.jl:78
 [5] FreeUnits at /Users/tomyun/.julia/packages/Unitful/9XsxK/src/types.jl:92 [inlined]
 [6] |>(::Quantity{Int64,𝐋¹ᐟ²,Unitful.FreeUnits{(m¹ᐟ²,),𝐋¹ᐟ²,nothing}}, ::Unitful.FreeUnits{(cm¹ᐟ²,),𝐋¹ᐟ²,nothing}) at ./operators.jl:823
 [7] top-level scope at REPL[28]:1
```
