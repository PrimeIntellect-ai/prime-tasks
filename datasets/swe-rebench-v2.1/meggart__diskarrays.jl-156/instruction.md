Indexing with not enough dimensions does not error
On current master trying to access a DiskArray with not enough indices does not error but normal arrays error and DiskArrays used to error.

```
julia> using DiskArrays.TestTypes

julia> u = UnchunkedDiskArray(rand(275,305,36))
275×305×36 UnchunkedDiskArray{Float64, 3, Array{Float64, 3}}

Unchunked

julia> u[1,1] # would have expected a BoundsError here
0.6956590014976399
```
