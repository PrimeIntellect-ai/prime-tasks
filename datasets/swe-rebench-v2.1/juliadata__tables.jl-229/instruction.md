`Tables.columntable(NamedTuple[])` errors
It feels like `Tables.columntable()` should simply return `NamedTuple[]` if it is passed an empty collection.  As it stands, it currently errors:

```julia
julia> Tables.columntable(NamedTuple[])
ERROR: ArgumentError: type does not have a definite number of fields
Stacktrace:
 [1] fieldcount(::Any) at ./reflection.jl:725
 [2] buildcolumns at /home/sabae/.julia/packages/Tables/8Ud85/src/fallbacks.jl:206 [inlined]
 [3] columns at /home/sabae/.julia/packages/Tables/8Ud85/src/fallbacks.jl:253 [inlined]
 [4] columntable(::Array{NamedTuple,1}) at /home/sabae/.julia/packages/Tables/8Ud85/src/namedtuples.jl:158
 [5] top-level scope at REPL[2]:1
```
