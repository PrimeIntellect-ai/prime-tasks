It seems the nested field of value `nothing` is not supported
MWE:

```
julia> @option struct OptionA
                         name::Union{Nothing,String}=nothing
                         int::Int = 1
                     end

julia> @option struct OptionB
                         name::Union{Nothing,OptionA}=nothing
                         int::Int = 1
                     end

julia> from_dict(OptionB, Dict{String,Any}("name"=>nothing))
ERROR: option name must be specified using an AbstractDict
Stacktrace:
  [1] error(s::String)
    @ Base ./error.jl:33
  [2] from_kwargs_option_key!(f::Configurations.var"#13#15"{Symbol, Base.Iterators.Pairs{Union{}, Union{}, Tuple{}, NamedTuple{(), Tuple{}}}}, d::Dict{String, Any}, #unused#::Type{OptionA}, name::Symbol, key::Symbol, kw::Base.Iterators.Pairs{Union{}, Union{}, Tuple{}, NamedTuple{(), Tuple{}}})
    @ Configurations ~/.julia/packages/Configurations/CguPm/src/parse.jl:281
  [3] from_kwargs_option_key!(f::Configurations.var"#13#15"{Symbol, Base.Iterators.Pairs{Union{}, Union{}, Tuple{}, NamedTuple{(), Tuple{}}}}, d::Dict{String, Any}, #unused#::Type{Union{Nothing, OptionA}}, name::Symbol, key::Symbol, kw::Base.Iterators.Pairs{Union{}, Union{}, Tuple{}, NamedTuple{(), Tuple{}}})
    @ Configurations ~/.julia/packages/Configurations/CguPm/src/parse.jl:291
  [4] #12
    @ ~/.julia/packages/Configurations/CguPm/src/parse.jl:250 [inlined]
  [5] foreach_keywords!(f::Configurations.var"#12#14"{Base.Iterators.Pairs{Union{}, Union{}, Tuple{}, NamedTuple{(), Tuple{}}}, Dict{String, Any}, Nothing}, list::Dict{String, Any}, #unused#::Type{OptionB})
    @ Configurations ~/.julia/packages/Configurations/CguPm/src/parse.jl:355
  [6] #unsafe_from_underscore_kwargs!#11
    @ ~/.julia/packages/Configurations/CguPm/src/parse.jl:247 [inlined]
  [7] unsafe_from_underscore_kwargs!
    @ ~/.julia/packages/Configurations/CguPm/src/parse.jl:247 [inlined]
  [8] #from_underscore_kwargs!#10
    @ ~/.julia/packages/Configurations/CguPm/src/parse.jl:243 [inlined]
  [9] from_underscore_kwargs! (repeats 2 times)
    @ ~/.julia/packages/Configurations/CguPm/src/parse.jl:242 [inlined]
 [10] from_dict(::Type{OptionB}, d::Dict{String, Any}; kw::Base.Iterators.Pairs{Union{}, Union{}, Tuple{}, NamedTuple{(), Tuple{}}})
    @ Configurations ~/.julia/packages/Configurations/CguPm/src/parse.jl:29
 [11] from_dict(::Type{OptionB}, d::Dict{String, Any})
    @ Configurations ~/.julia/packages/Configurations/CguPm/src/parse.jl:29
 [12] top-level scope
    @ REPL[27]:1
```

### Additional contract requirements

- `from_dict(T, d)` accepts `nothing` as the value of a field whose declared type is `Union{Nothing, Option}` (a nested option type), producing the option with that field set to `nothing`.
