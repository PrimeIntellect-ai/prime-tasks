@static if inside @option
While trying to port Pluto to Configurations.jl, I found this:
```julia
julia> using Configurations

julia> f() = 123
f (generic function with 1 method)

julia> @option struct A
           x=f()
       end

julia> @option struct B
           x=1
           @static if true
               y=f()
           end
       end

julia> A()
A(;
)

julia> A(1)
A(;
    x = 1,
)

julia> B()
ERROR: MethodError: no method matching B(::Int64)
Closest candidates are:
  B(; x) at none:0
Stacktrace:
 [1] B(; x::Int64)
   @ Main ./none:0
 [2] B()
   @ Main ./none:0
 [3] top-level scope
   @ REPL[9]:1

julia> B(1,2)
ERROR: MethodError: no method matching B(::Int64, ::Int64)
Stacktrace:
 [1] top-level scope
   @ REPL[5]:1

```

We use `@static` here: https://github.com/fonsp/Pluto.jl/blob/main/src/Configuration.jl#L84

### Additional contract requirements

When an `@static if` branch inside an `@option` definition is active, its declared fields are included in the generated option type. Those fields participate in the type's normal constructor behavior: declared defaults are applied when omitted, and positional construction accepts values for all declared fields.
