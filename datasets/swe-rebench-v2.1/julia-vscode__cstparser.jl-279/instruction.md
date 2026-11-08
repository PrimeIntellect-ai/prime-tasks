Binary op parsing incorrect order
As you can see `*` appears after `2` in the order for `s`

ref https://github.com/domluna/JuliaFormatter.jl/issues/410

```
julia> s = "*(p) * 2"
"*(p) * 2"

julia> s0 = "(p) * 2"
"(p) * 2"

julia> x = CSTParser.parse(s)
  1:8   call
  1:1    OP: *
  2:2    p
  3:3    INTEGER: 2

julia> y = CSTParser.parse(s0)
  1:7   call
  1:2    OP: *
  3:6    brackets
  3:3     p
  7:7    INTEGER: 2

julia> collect(x)
6-element Vector{Any}:
   1:1   OP: *
   1:1   (
   1:1   p
   1:2   )
   1:1   INTEGER: 2
   1:2   OP: *

julia> collect(y)
3-element Vector{Any}:
   1:4   brackets
  1:1    p
   1:2   OP: *
   1:1   INTEGER: 2

```
