Parsing list comprehensions
See context here: https://github.com/domluna/JuliaFormatter.jl/issues/678
```
julia> s = raw"""
       Y = ishi.(@view X[:, i] for i in 1:samples)
       """
"Y = ishi.(@view X[:, i] for i in 1:samples)\n"

julia>

julia> format_text(s) |> print
ERROR: Parsing error for input occurred on line 1, offset: 42
Stacktrace:
 [1] error
   @ ./error.jl:35
 [2] format_text(text::String, style::DefaultStyle, opts::JuliaFormatter.Options)
   @ JuliaFormatter ~/.julia/dev/JuliaFormatter/src/JuliaFormatter.jl:673
 [3] format_text(text::String, style::DefaultStyle; kwargs::Base.Pairs{Symbol, Union{}, Tuple{}, NamedTuple{(), Tuple{}}})
   @ JuliaFormatter ~/.julia/dev/JuliaFormatter/src/JuliaFormatter.jl:647
 [4] format_text
   @ ~/.julia/dev/JuliaFormatter/src/JuliaFormatter.jl:644 [inlined]
 [5] #format_text#235
   @ ~/.julia/dev/JuliaFormatter/src/JuliaFormatter.jl:641 [inlined]
 [6] format_text(text::String)
   @ JuliaFormatter ~/.julia/dev/JuliaFormatter/src/JuliaFormatter.jl:640
 [7] top-level scope
   @ REPL[6]:1

julia>  using CSTParser

julia> CSTParser.parse(s)
  1:44    1:2   OP: =
  1:2    Y
  3:42     1:1   OP: .
  3:6     ishi
  7:41    tuple
  7:40     macrocall
  7:12      @view
 13:12      NOTHING: nothing
 13:20      ref
 13:13       X
 14:14       OP: :
 15:15       i
 21:40      for
 21:34         1:0   OP: =
 21:22        i
 23:31        call
 23:23         OP: :
 24:24         INTEGER: 1
 25:31         samples
 35:36       block
 35:36        errortoken( CSTParser.UnexpectedToken)
 35:36         )

julia>
```
