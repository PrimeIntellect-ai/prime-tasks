Inconsistent handling of Tuple and NamedTuple
Currently we have this:
```
julia> Tables.columns(NamedTuple{(:a, :b),Tuple{Int,Int}}[])
Tables.CopiedColumns{NamedTuple{(:a, :b),Tuple{Array{Int64,1},Array{Int64,1}}}}: (a = Int64[], b = Int64[])

julia> Tables.columntable(Tuple{Int,Int}[])
NamedTuple()
```
Is this intended?

(I know it is a corner case but I test against it in DataFrames.jl)

### Additional contract requirements

When an empty iterable has a known row type, converting it to columns must preserve the row type's available schema. For NamedTuple rows, preserve the declared column names and element types. For Tuple rows, expose one empty column per tuple element with the corresponding element type; tuple column names are not required to follow a particular naming convention.
