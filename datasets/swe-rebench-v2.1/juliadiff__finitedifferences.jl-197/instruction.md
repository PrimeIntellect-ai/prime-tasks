`to_vec` should make an empty vector for `CartesianIndex`
```julia
julia> to_vec(CartesianIndex(1))[1]
1-element Vector{Int64}:
 1
```
should be an empty vector instead
