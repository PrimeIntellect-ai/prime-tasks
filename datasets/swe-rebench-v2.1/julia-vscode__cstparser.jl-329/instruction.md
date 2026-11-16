Parsing `@doc` macro with trailing newline errors
It seems there is a problem with `@doc` + trailing newlines:
```julia
julia> using CSTParser

julia> CSTParser.has_error(CSTParser.parse("@doc(filter)"))
false

julia> CSTParser.has_error(CSTParser.parse("@doc filter"))
false

julia> CSTParser.has_error(CSTParser.parse("@doc(Base.filter)"))
false

julia> CSTParser.has_error(CSTParser.parse("@doc Base.filter"))
false

julia> CSTParser.has_error(CSTParser.parse("""
       @doc(filter)
       """))
true

julia> CSTParser.has_error(CSTParser.parse("""
       @doc filter
       """))
true

julia> CSTParser.has_error(CSTParser.parse("""
       @doc(Base.filter)
       """))
true

julia> CSTParser.has_error(CSTParser.parse("""
       @doc Base.filter
       """))
true
```
This came up in https://github.com/domluna/JuliaFormatter.jl/issues/555.
