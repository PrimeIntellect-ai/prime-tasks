Meta.parse on invalid syntax with enable_in_core!
I noticed that the errors are different:

```julia-repl
julia> Meta.parse("[(1,2]")
ERROR: Base.Meta.ParseError("unexpected \"]\" in argument list")
Stacktrace:
 [1] #parse#3
   @ ./meta.jl:237 [inlined]
 [2] parse(str::String; raise::Bool, depwarn::Bool)
   @ Base.Meta ./meta.jl:268
 [3] parse(str::String)
   @ Base.Meta ./meta.jl:268
 [4] top-level scope
   @ REPL[1]:1

julia> using JuliaSyntax

julia> JuliaSyntax.enable_in_core!()

julia> Meta.parse("[(1,2]")
ERROR: MethodError: Cannot `convert` an object of type JuliaSyntax.ParseError to an object of type String
Closest candidates are:
  convert(::Type{String}, ::String) at /Applications/Julia-1.7 x86.app/Contents/Resources/julia/share/julia/base/essentials.jl:223
  convert(::Type{T}, ::T) where T<:AbstractString at /Applications/Julia-1.7 x86.app/Contents/Resources/julia/share/julia/base/strings/basic.jl:231
  convert(::Type{T}, ::AbstractString) where T<:AbstractString at /Applications/Julia-1.7 x86.app/Contents/Resources/julia/share/julia/base/strings/basic.jl:232
  ...
Stacktrace:
 [1] Base.Meta.ParseError(msg::JuliaSyntax.ParseError)
   @ Base.Meta ./meta.jl:190
 [2] #parse#3
   @ ./meta.jl:237 [inlined]
 [3] parse(str::String; raise::Bool, depwarn::Bool)
   @ Base.Meta ./meta.jl:268
 [4] parse(str::String)
   @ Base.Meta ./meta.jl:268
 [5] top-level scope
   @ none:1
```

Not sure if this matters or not, just thought i would report it

### Additional contract requirements

- `JuliaSyntax.enable_in_core!()` makes subsequent `Meta.parse` calls use the JuliaSyntax parser.
- While Core integration is enabled, `Meta.parse` on invalid syntax raises `JuliaSyntax.ParseError`.
- `JuliaSyntax.disable_in_core!()` reverses the effect of `JuliaSyntax.enable_in_core!()`: after it is called, `Meta.parse` is handled by the default parser again, so invalid syntax raises `Base.Meta.ParseError`.


- With Core integration enabled, `Meta.parse("x + 1", 1)` must return `(:(x + 1), 6)`, `Meta.parse("x + 1\n(y)", 1)` must return `(:(x + 1), 6)`, and `Meta.parse("x + 1\n(y)", 6)` must return `(:y, 10)`.
