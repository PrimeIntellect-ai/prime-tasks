CircularBuffer push! increases size even if value can't be converted
Reproducible with the following steps:
```
julia> using DataStructures
julia> cb = CircularBuffer{Int}(5);
julia> size(cb)
(0,)
julia> push!(cb, 1.5)
ERROR: InexactError: Int64(1.5)
[...]
julia> size(cb)
(1,)
pkg> status
[...]
  [864edb3b] DataStructures v0.18.9
[...]
```

This seems strongly like unexpected behavior to me and should probably be fixed.
