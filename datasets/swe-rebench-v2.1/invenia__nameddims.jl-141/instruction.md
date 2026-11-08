Broadcasting ambiguity
MWE:

```julia
using NamedDims
a = NamedDimsArray([1,1], :a)
b = (1,1)
g(x, y) = x + 1
g.(a, b)
```

```
MethodError: Base.Broadcast.BroadcastStyle(::NamedDims.NamedDimsStyle{Base.Broadcast.DefaultArrayStyle{1}}, ::Base.Broadcast.Style{Tuple}) is ambiguous.
```
<details> <summary> more ... </summary>

```
MethodError: Base.Broadcast.BroadcastStyle(::NamedDims.NamedDimsStyle{Base.Broadcast.DefaultArrayStyle{1}}, ::Base.Broadcast.Style{Tuple}) is ambiguous. Candidates:
  Base.Broadcast.BroadcastStyle(a::Base.Broadcast.AbstractArrayStyle, ::Base.Broadcast.Style{Tuple}) in Base.Broadcast at broadcast.jl:136
  Base.Broadcast.BroadcastStyle(::NamedDims.NamedDimsStyle{A}, b::B) where {A, B} in NamedDims at /Users/fabiangreimel/.julia/packages/NamedDims/12b8d/src/broadcasting.jl:28
  Base.Broadcast.BroadcastStyle(::Base.Broadcast.BroadcastStyle, ::Base.Broadcast.BroadcastStyle) in Base.Broadcast at broadcast.jl:130
[HIDDEN]
result_style(::NamedDims.NamedDimsStyle{Base.Broadcast.DefaultArrayStyle{1}}, ::Base.Broadcast.Style{Tuple}) at broadcast.jl:445
combine_styles(::NamedDimsArray{(:a,),Int64,1,Array{Int64,1}}, ::Tuple{Int64,Int64}) at broadcast.jl:421
broadcasted(::Function, ::NamedDimsArray{(:a,),Int64,1,Array{Int64,1}}, ::Tuple{Int64,Int64}) at broadcast.jl:1263
top-level scope at aog.jl:185
include_string(::Function, ::Module, ::String, ::String) at loading.jl:1088
```

</details>

this bit me here https://github.com/JuliaPlots/AlgebraOfGraphics.jl/pull/80 and here https://github.com/JuliaPlots/Makie.jl/issues/709

### Additional contract requirements

When broadcasting a `NamedDimsArray` with a tuple, broadcasting must work without a style ambiguity in either operand order. The result must contain the elementwise values and remain a `NamedDimsArray` with the original dimension names.
