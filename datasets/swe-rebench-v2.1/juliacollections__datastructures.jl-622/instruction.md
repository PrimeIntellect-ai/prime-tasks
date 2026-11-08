DataStructures.jl pirates zip()
```
julia> zip()
zip()

julia> using DataStructures

julia> zip()
ERROR: ArgumentError: collection must be non-empty
Stacktrace:
 [1] _findmin(::Tuple{}, ::Colon) at ./array.jl:2201
 [2] findmin(::Tuple{}) at ./array.jl:2195
 [3] DataStructures.ZippedSparseIntSetIterator(; exclude::Tuple{}) at /home/takafumi/.julia/dev/DataStructures/src/sparse_int_set.jl:208
 [4] DataStructures.ZippedSparseIntSetIterator() at /home/takafumi/.julia/dev/DataStructures/src/sparse_int_set.jl:208
 [5] zip(; kwargs::Base.Iterators.Pairs{Union{},Union{},Tuple{},NamedTuple{(),Tuple{}}}) at /home/takafumi/.julia/dev/DataStructures/src/sparse_int_set.jl:213
 [6] zip() at /home/takafumi/.julia/dev/DataStructures/src/sparse_int_set.jl:213
 [7] top-level scope at REPL[4]:1

(tmp_y5_3d7e.julia_tmp) pkg> st
Status `/tmp/tmp_y5_3d7e.julia_tmp/Project.toml`
  [864edb3b] DataStructures v0.17.15 `~/.julia/dev/DataStructures`
  [44cfe95a] Pkg
```
