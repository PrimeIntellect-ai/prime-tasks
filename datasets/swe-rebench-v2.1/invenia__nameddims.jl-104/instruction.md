Indexing by BitArray{N}
This doesn’t error, but why should it have name `:x` not `:z`? Probably it should have neither (ref #69):
```
julia> nda = NamedDimsArray(rand(1:9, 3,3,3), (:x, :y, :z));

julia> nda[rand(3,3,3) .> 0.5]
17-element NamedDimsArray{(:x,),Int64,1,Array{Int64,1}}:
```
The case of `BitArray{1}` works correctly:
```
julia> nda[rand(3) .> 0.3, 1, :]
2×3 NamedDimsArray{(:x, :z),Int64,2,Array{Int64,2}}:
```
