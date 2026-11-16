`show` for certain symbols (`e` and `f`) has extra space
Minor issue but for some reason there is an extra space for only the symbols `e` and `f`:

```julia
julia> @variables a b c d e f g h i
9-element Vector{Num}:
 a
 b
 c
 d
  e
  f
 g
 h
 i

julia> [a b c; d e f; g h i]
3×3 Matrix{Num}:
 a  b   c
 d   e   f
 g  h   i
```
