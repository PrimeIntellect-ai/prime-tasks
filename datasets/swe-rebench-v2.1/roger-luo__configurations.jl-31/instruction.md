Union{Nothing,String} not allowed?
I wonder why this isn't working, can it be made to work?

```julia
julia> @option struct OptionA
                  name::Union{Nothing,String}=nothing
                  int::Int = 1
              end

julia> Configurations.from_kwargs(OptionA, name="asdf")
ERROR: ArgumentError: invalid key name, possible keys are: int
Stacktrace:
 [1] validate_keywords(::Type{OptionA}; kw::Base.Iterators.Pairs{Symbol, String, Tuple{Symbol}, NamedTuple{(:name,), Tuple{String}}})
   @ Configurations ~/.julia/packages/Configurations/CZY8K/src/Configurations.jl:416
 [2] #from_kwargs#20
   @ ~/.julia/packages/Configurations/CZY8K/src/Configurations.jl:459 [inlined]
 [3] top-level scope
   @ REPL[6]:1
```

(The workaround is to use `Any` as field type.)

### Additional contract requirements

- `Configurations.from_kwargs(::Type{T}; kw...)` builds an instance of the option type `T` from keyword arguments. A keyword may address a nested option field using the underscore convention (for example `opt_name` for the `name` field of the `opt` sub-option). A field whose declared type is `Union{Nothing,String}` (or any `Union` that includes a non-option type) is a valid keyword target. Supplying a keyword that is not a valid key throws an `ArgumentError`.
- `Configurations.validate_keywords(::Type{T}; kw...)` returns `nothing` when every supplied keyword is a valid key for `T`, and otherwise throws an `ArgumentError`.
