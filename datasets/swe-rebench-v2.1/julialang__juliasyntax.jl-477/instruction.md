Parentheses not required warning in `using A: (..)`
In this case, parentheses are requires, but the warning says they are not:
```julia
julia> JuliaSyntax.parse(Expr, "using A: (..)")
ERROR: ParseError:
# Warning @ line 1:10
using A: (..)
#        └──┘ ── parentheses are not required here
Stacktrace:
 [1] _parse(rule::Symbol, need_eof::Bool, ::Type{…}, text::String, index::Int64; version::VersionNumber, ignore_trivia::Bool, filename::Nothing, first_line::Int64, ignore_errors::Bool, ignore_warnings::Bool, kws::@Kwargs{})
   @ JuliaSyntax ~/.julia/dev/JuliaSyntax/src/parser_api.jl:93
 [2] _parse (repeats 2 times)
   @ JuliaSyntax ~/.julia/dev/JuliaSyntax/src/parser_api.jl:77 [inlined]
 [3] parsestmt(::Type{Expr}, text::String)
   @ JuliaSyntax ~/.julia/dev/JuliaSyntax/src/parser_api.jl:140
 [4] parse(::Type, ::Vararg{Any}; kwargs::@Kwargs{})
   @ JuliaSyntax ./deprecated.jl:116
 [5] parse(::Type, ::Vararg{Any})
   @ JuliaSyntax ./deprecated.jl:113
 [6] top-level scope
   @ REPL[19]:1
Some type information was truncated. Use `show(err)` to see complete types.

julia> JuliaSyntax.parse(Expr, "using A: ..")
ERROR: ParseError:
# Error @ line 1:12
using A: ..
#          └ ── premature end of input
Stacktrace:
 [1] _parse(rule::Symbol, need_eof::Bool, ::Type{…}, text::String, index::Int64; version::VersionNumber, ignore_trivia::Bool, filename::Nothing, first_line::Int64, ignore_errors::Bool, ignore_warnings::Bool, kws::@Kwargs{})
   @ JuliaSyntax ~/.julia/dev/JuliaSyntax/src/parser_api.jl:93
 [2] _parse (repeats 2 times)
   @ JuliaSyntax ~/.julia/dev/JuliaSyntax/src/parser_api.jl:77 [inlined]
 [3] parsestmt(::Type{Expr}, text::String)
   @ JuliaSyntax ~/.julia/dev/JuliaSyntax/src/parser_api.jl:140
 [4] parse(::Type, ::Vararg{Any}; kwargs::@Kwargs{})
   @ JuliaSyntax ./deprecated.jl:116
 [5] parse(::Type, ::Vararg{Any})
   @ JuliaSyntax ./deprecated.jl:113
 [6] top-level scope
   @ REPL[20]:1
Some type information was truncated. Use `show(err)` to see complete types.
```
