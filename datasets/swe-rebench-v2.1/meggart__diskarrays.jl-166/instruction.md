numind and CartesianIndex
I'm getting a lot of errors like this on DiskArrays 0.4, maybe there is some missing dispatch for CartesianIndex? It looks like it may be missing higher up. Sorry no MWE yet.

```julia
  MethodError: no method matching numind(::CartesianIndex{3})

  Closest candidates are:
    numind(::AbstractArray{Bool})
     @ DiskArrays ~/.julia/dev/DiskArrays/src/batchgetindex.jl:80
    numind(::Union{AbstractArray{<:Integer}, AbstractArray{<:CartesianIndex}})
     @ DiskArrays ~/.julia/dev/DiskArrays/src/batchgetindex.jl:81

  Stacktrace:
    [1] is_sparse_index(ids::CartesianIndex{3}; density_threshold::Float64)
      @ DiskArrays ~/.julia/dev/DiskArrays/src/batchgetindex.jl:84
    [2] need_batch_index(i::CartesianIndex{3}, cs::Tuple{DiskArrays.RegularChunks, DiskArrays.RegularChunks, DiskArrays.RegularChunks}, batchstrat::DiskArrays.SubRanges{DiskArrays.NoStepRange})
      @ DiskArrays ~/.julia/dev/DiskArrays/src/diskarray.jl:71
    [3] _need_batch(cs::Tuple{DiskArrays.RegularChunks, DiskArrays.RegularChunks, DiskArrays.RegularChunks}, i::Tuple{CartesianIndex{3}}, batchstrat::DiskArrays.SubRanges{DiskArrays.NoStepRange})
      @ DiskArrays ~/.julia/dev/DiskArrays/src/diskarray.jl:57
    [4] need_batch(a::Rasters.RasterDiskArray{GRDsource, Float32, 3, Array{Float32, 3}, DiskArrays.GridChunks{3, Tuple{DiskArrays.RegularChunks, DiskArrays.RegularChunks, DiskArrays.RegularChunks}}, DiskArray
s.Unchunked{DiskArrays.SubRanges{DiskArrays.NoStepRange}}, Nothing}, i::Tuple{CartesianIndex{3}})
      @ DiskArrays ~/.julia/dev/DiskArrays/src/diskarray.jl:54
    [5] setindex_disk!(a::Rasters.RasterDiskArray{GRDsource, Float32, 3, Array{Float32, 3}, DiskArrays.GridChunks{3, Tuple{DiskArrays.RegularChunks, DiskArrays.RegularChunks, DiskArrays.RegularChunks}}, DiskA
rrays.Unchunked{DiskArrays.SubRanges{DiskArrays.NoStepRange}}, Nothing}, v::Array{Float32, 3}, i::CartesianIndex{3})
      @ DiskArrays ~/.julia/dev/DiskArrays/src/diskarray.jl:314
    [6] setindex!(a::Rasters.RasterDiskArray{GRDsource, Float32, 3, Array{Float32, 3}, DiskArrays.GridChunks{3, Tuple{DiskArrays.RegularChunks, DiskArrays.RegularChunks, DiskArrays.RegularChunks}}, DiskArrays
.Unchunked{DiskArrays.SubRanges{DiskArrays.NoStepRange}}, Nothing}, v::Array{Float32, 3}, i::CartesianIndex{3})
      @ DiskArrays ~/.julia/dev/DiskArrays/src/diskarray.jl:353
    [7] setindex!(a::Rasters.RasterDiskArray{GRDsource, Float32, 3, Array{Float32, 3}, DiskArrays.GridChunks{3, Tuple{DiskArrays.RegularChunks, DiskArrays.RegularChunks, DiskArrays.RegularChunks}}, DiskArrays
.Unchunked{DiskArrays.SubRanges{DiskArrays.NoStepRange}}, Nothing}, v::Float32, i::CartesianIndex{3})
      @ DiskArrays ~/.julia/dev/DiskArrays/src/diskarray.jl:357
    [8] setindex!
      @ ~/.julia/dev/DimensionalData/src/array/indexing.jl:259 [inlined]
    [9] macro expansion
      @ ./broadcast.jl:1004 [inlined]
   [10] macro expansion
      @ ./simdloop.jl:77 [inlined]
   [11] copyto!
      @ ./broadcast.jl:1003 [inlined]
   [12] copyto!
      @ ./broadcast.jl:956 [inlined]
   [13] materialize!
      @ ./broadcast.jl:914 [inlined]
   [14] materialize!
      @ ./broadcast.jl:911 [inlined]
   [15] broadcast!(f::Rasters.var"#751#755"{Float32, typeof(first), Tuple{Raster{Float32, 3, Tuple{X{Projected{Float64, LinRange{Float64, Int64}, ForwardOrdered, Regular{Float64}, Intervals{Start}, Metadata{G
RDsource, Dict{String, Any}}, ProjString, Nothing, X{Colon}}}, Y{Projected{Float64, LinRange{Float64, Int64}, ReverseOrdered, Regular{Float64}, Intervals{Start}, Metadata{GRDsource, Dict{String, Any}}, ProjSt
ring, Nothing, Y{Colon}}}, Band{Categorical{Int64, UnitRange{Int64}, ForwardOrdered, NoMetadata}}}, Tuple{}, Array{Float32, 3}, Symbol, Metadata{GRDsource, Dict{String, Any}}, Float32}, Raster{Float32, 3, Tup
le{X{Projected{Float64, LinRange{Float64, Int64}, ForwardOrdered, Regular{Float64}, Intervals{Start}, Metadata{GRDsource, Dict{String, Any}}, ProjString, Nothing, X{Colon}}}, Y{Projected{Float64, LinRange{Flo
at64, Int64}, ReverseOrdered, Regular{Float64}, Intervals{Start}, Metadata{GRDsource, Dict{String, Any}}, ProjString, Nothing, Y{Colon}}}, Band{Categorical{Int64, UnitRange{Int64}, ForwardOrdered, NoMetadata}
}}, Tuple{}, Array{Float32, 3}, Symbol, Metadata{GRDsource, Dict{String, Any}}, Float32}}}, dest::Raster{Float32, 3, Tuple{X{Projected{Float64, LinRange{Float64, Int64}, ForwardOrdered, Regular{Float64}, Inte
rvals{Start}, Metadata{GRDsource, Dict{String, Any}}, ProjString, Nothing, X{Colon}}}, Y{Projected{Float64, LinRange{Float64, Int64}, ReverseOrdered, Regular{Float64}, Intervals{Start}, Metadata{GRDsource, Di
ct{String, Any}}, ProjString, Nothing, Y{Colon}}}, Band{Categorical{Int64, UnitRange{Int64}, ForwardOrdered, NoMetadata}}}, Tuple{}, Rasters.RasterDiskArray{GRDsource, Float32, 3, Array{Float32, 3}, DiskArray
s.GridChunks{3, Tuple{DiskArrays.RegularChunks, DiskArrays.RegularChunks, DiskArrays.RegularChunks}}, DiskArrays.Unchunked{DiskArrays.SubRanges{DiskArrays.NoStepRange}}, Nothing}, Symbol, Metadata{GRDsource,
Dict{String, Any}}, Float32}, As::DimSelectors{Tuple{X{At{Float64, Float64, Nothing}}, Y{At{Float64, Float64, Nothing}}, Band{At{Int64, Float64, Nothing}}}, 3, Tuple{X{Projected{Float64, LinRange{Float64, Int
64}, ForwardOrdered, Regular{Float64}, Intervals{Start}, Metadata{GRDsource, Dict{String, Any}}, ProjString, Nothing, X{Colon}}}, Y{Projected{Float64, LinRange{Float64, Int64}, ReverseOrdered, Regular{Float64
}, Intervals{Start}, Metadata{GRDsource, Dict{String, Any}}, ProjString, Nothing, Y{Colon}}}, Band{Categorical{Int64, UnitRange{Int64}, ForwardOrdered, NoMetadata}}}, Tuple{At{Float64, Float64, Nothing}, At{F
loat64, Float64, Nothing}, At{Int64, Float64, Nothing}}})
      @ Base.Broadcast ./broadcast.jl:880
```
