ustrip() does not work with `Base.TwicePrecision`
MWE:

```julia
xs = 1:0.1:2
ustrip.(xs)
```

This errors out:
```
ERROR: MethodError: no method matching ustrip(::Base.TwicePrecision{Float64})
The function `ustrip` exists, but no method is defined for this combination of argument types.

Closest candidates are:
  ustrip(::Missing)
   @ Unitful ~/.julia/packages/Unitful/R4J37/src/utils.jl:59
  ustrip(::Type, ::Unitful.Units, ::Any)
   @ Unitful ~/.julia/packages/Unitful/R4J37/src/utils.jl:38
  ustrip(::LinearAlgebra.SymTridiagonal)
   @ Unitful ~/.julia/packages/Unitful/R4J37/src/utils.jl:101
  ...

Stacktrace:
 [1] broadcasted(::Base.Broadcast.DefaultArrayStyle{1}, x::typeof(ustrip), r::StepRangeLen{Float64, Base.TwicePrecision{Float64}, Base.TwicePrecision{Float64}, Int64})
   @ Unitful ~/.julia/packages/Unitful/R4J37/src/range.jl:159
 [2] broadcasted(::typeof(ustrip), ::StepRangeLen{Float64, Base.TwicePrecision{Float64}, Base.TwicePrecision{Float64}, Int64})
   @ Base.Broadcast ./broadcast.jl:1320
 [3] top-level scope
   @ REPL[10]:2
```
