Bug In Symbolics.coeff, quite strange
```
julia> @variables x a b c d
6-element Vector{Num}:
 x
 a
 b
 c
 d

julia> Symbolics.coeff(c + (a + b*x)*d, x)
ERROR: TypeError: non-boolean (SymbolicUtils.BasicSymbolic{Bool}) used in boolean context
Stacktrace:
  [1] _all(f::typeof(iszero), itr::Vector{Any}, ::Colon)
    @ Base ./reduce.jl:1314
  [2] all(f::Function, a::Vector{Any}; dims::Function)
    @ Base ./reducedim.jl:995
  [3] coeff(p::SymbolicUtils.BasicSymbolic{Real}, sym::SymbolicUtils.BasicSymbolic{Real})
    @ Symbolics ~/.julia/dev/Symbolics/src/utils.jl:359
  [4] (::Symbolics.var"#82#84")(::Pair{Any, Any})
    @ Symbolics ./none:0
  [5] (::Base.MappingRF{Symbolics.var"#82#84", Base.BottomRF{typeof(Base.add_sum)}})(acc::Base._InitialValue, x::Pair{Any, Any})
    @ Base ./reduce.jl:100
  [6] _foldl_impl(op::Base.MappingRF{Symbolics.var"#82#84", Base.BottomRF{typeof(Base.add_sum)}}, init::Base._InitialValue, itr::Dict{Any, Any})
    @ Base ./reduce.jl:58
  [7] foldl_impl(op::Base.MappingRF{Symbolics.var"#82#84", Base.BottomRF{typeof(Base.add_sum)}}, nt::Base._InitialValue, itr::Dict{Any, Any})
    @ Base ./reduce.jl:48
  [8] mapfoldl_impl(f::typeof(identity), op::typeof(Base.add_sum), nt::Base._InitialValue, itr::Base.Generator{Dict{…}, Symbolics.var"#82#84"})
    @ Base ./reduce.jl:44
  [9] mapfoldl(f::Function, op::Function, itr::Base.Generator{Dict{Any, Any}, Symbolics.var"#82#84"}; init::Base._InitialValue)
    @ Base ./reduce.jl:175
 [10] mapfoldl
    @ ./reduce.jl:175 [inlined]
 [11] mapreduce
    @ ./reduce.jl:307 [inlined]
 [12] sum(f::Function, a::Base.Generator{Dict{Any, Any}, Symbolics.var"#82#84"})
    @ Base ./reduce.jl:532
 [13] sum(a::Base.Generator{Dict{Any, Any}, Symbolics.var"#82#84"}; kw::@Kwargs{})
    @ Base ./reduce.jl:561
 [14] sum
    @ ./reduce.jl:561 [inlined]
 [15] coeff(p::Num, sym::Num)
    @ Symbolics ~/.julia/dev/Symbolics/src/utils.jl:354
 [16] top-level scope
    @ REPL[108]:1
Some type information was truncated. Use `show(err)` to see complete types.
```

note that this:
```
julia> Symbolics.coeff(c + a*d + b*x*d,x)
b*d
```
works correctly
