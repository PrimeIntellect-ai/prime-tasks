Multidimensional parse issue
These should be the same no?

```
julia> str |> print
[1;; 2]
julia> x |> print
[
    1;;
    2
]
julia> CSTParser.parse(str)
  1:7   ncat
  1:0    2
  1:4    INTEGER: 1
  5:5    INTEGER: 2

julia>

julia> CSTParser.parse(x)
  1:17  vcat
  1:10   row
  1:8     INTEGER: 1
  9:10    INTEGER: 2
```
