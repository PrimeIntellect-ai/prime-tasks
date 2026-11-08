Broadcasting operation between symbolic array and symbolic variable errors out
MWE:
```julia
julia> @variables t F(t)[1:2] = [0.0, 0.0]
julia> @parameters m = 1.0
julia> collect(F ./ m)
```
Error:
```
ERROR: MethodError: no method matching /(::Term{Real, Base.ImmutableDict{DataType, Any}}, ::Base.RefValue{Sym{Real, Base.ImmutableDict{DataType, Any}}})
Closest candidates are:
  /(::Any, ::ChainRulesCore.AbstractThunk) at ~/.julia/packages/ChainRulesCore/ctmSK/src/tangent_types/thunks.jl:37
  /(::Union{Num, SymbolicUtils.Symbolic}, ::Unitful.AbstractQuantity) at ~/.julia/packages/ModelingToolkit/pFDAD/src/systems/validation.jl:2
  /(::ChainRulesCore.AbstractThunk, ::Any) at ~/.julia/packages/ChainRulesCore/ctmSK/src/tangent_types/thunks.jl:36
  ...
Stacktrace:
  [1] (::Symbolics.var"#97#102"{Symbolics.var"#97#98#103"})(x::Term{Any, Nothing}, f::Function, args::Vector{Any}; kws::Base.Pairs{Symbol, Union{}, Tuple{}, NamedTuple{(), Tuple{}}})
    @ Symbolics ~/.julia/packages/Symbolics/4VdEG/src/arrays.jl:579
  [2] (::Symbolics.var"#97#102"{Symbolics.var"#97#98#103"})(x::Term{Any, Nothing}, f::Function, args::Vector{Any})
    @ Symbolics ~/.julia/packages/Symbolics/4VdEG/src/arrays.jl:561
  [3] prewalk_if(cond::Symbolics.var"#99#105", f::Metatheory.Rewriters.PassThrough{Metatheory.Rewriters.Chain}, t::Term{Any, Nothing}, similarterm::Symbolics.var"#97#102"{Symbolics.var"#97#98#103"})
    @ Symbolics ~/.julia/packages/Symbolics/4VdEG/src/arrays.jl:605
  [4] replace_by_scalarizing(ex::Term{Any, Nothing}, dict::Dict{Sym{Int64, Nothing}, Int64})
    @ Symbolics ~/.julia/packages/Symbolics/4VdEG/src/arrays.jl:597
  [5] scalarize(arr::Symbolics.ArrayOp{AbstractVector{Any}}, idx::Tuple{Int64})
    @ Symbolics ~/.julia/packages/Symbolics/4VdEG/src/arrays.jl:709
  [6] scalarize(arr::Term{Any, Nothing})
    @ Symbolics ~/.julia/packages/Symbolics/4VdEG/src/arrays.jl:731
  [7] (::Symbolics.var"#118#119")(i::Tuple{Int64})
    @ Symbolics ~/.julia/packages/Symbolics/4VdEG/src/arrays.jl:727
  [8] iterate
    @ ./generator.jl:47 [inlined]
  [9] collect(itr::Base.Generator{Base.Iterators.ProductIterator{Tuple{UnitRange{Int64}}}, Symbolics.var"#118#119"})
    @ Base ./array.jl:724
 [10] map(f::Function, A::Base.Iterators.ProductIterator{Tuple{UnitRange{Int64}}})
    @ Base ./abstractarray.jl:2896
 [11] scalarize(arr::Symbolics.Arr{Any, 1})
    @ Symbolics ~/.julia/packages/Symbolics/4VdEG/src/arrays.jl:726
 [12] collect(x::Symbolics.Arr{Any, 1})
    @ Symbolics ~/.julia/packages/Symbolics/4VdEG/src/arrays.jl:743
 [13] top-level scope
    @ REPL[12]:
```

As far as I can see, there's some issue with a `Ref` creeping into the symbolic equation
