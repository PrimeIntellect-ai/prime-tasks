getindex with empty index
While trying to update NCDatasets.jl to DiskArrays 0.4.4, test where I index with an empty array of indices fails. I can reproduce this issue with NetCDF.jl.

```julia
import NCDatasets

NCDatasets.Dataset("test.nc","c") do ds
    NCDatasets.defVar(ds,"var",zeros(10),("time",))
end

using NetCDF

data = NetCDF.open("test.nc","var") do ncv
   ncv[Int[]] # error
end
```

The full error message is:

```
julia> include("/home/abarth/.julia/dev/NCDatasets/test/test_empty.jl");
ERROR: LoadError: MethodError: reducing over an empty collection is not allowed; consider supplying `init` to the reducer
Stacktrace:
  [1] reduce_empty(op::Base.MappingRF{Base.ExtremaMap{typeof(identity)}, typeof(Base._extrema_rf)}, ::Type{Int64})
    @ Base ./reduce.jl:361
  [2] reduce_empty_iter
    @ ./reduce.jl:384 [inlined]
  [3] mapreduce_empty_iter(f::Function, op::Function, itr::Vector{Int64}, ItrEltype::Base.HasEltype)
    @ Base ./reduce.jl:380
  [4] _mapreduce
    @ ./reduce.jl:432 [inlined]
  [5] _mapreduce_dim
    @ ./reducedim.jl:365 [inlined]
  [6] mapreduce
    @ ./reducedim.jl:357 [inlined]
  [7] _extrema
    @ ./reducedim.jl:1015 [inlined]
  [8] _extrema
    @ ./reducedim.jl:1014 [inlined]
  [9] extrema
    @ ./reducedim.jl:1010 [inlined]
 [10] span(v::Vector{Int64})
    @ DiskArrays ~/.julia/packages/DiskArrays/6JA8Z/src/batchgetindex.jl:70
 [11] #is_sparse_index#13
    @ ~/.julia/packages/DiskArrays/6JA8Z/src/batchgetindex.jl:84 [inlined]
 [12] is_sparse_index
    @ ~/.julia/packages/DiskArrays/6JA8Z/src/batchgetindex.jl:83 [inlined]
 [13] need_batch_index
    @ ~/.julia/packages/DiskArrays/6JA8Z/src/diskarray.jl:72 [inlined]
 [14] _need_batch
    @ ~/.julia/packages/DiskArrays/6JA8Z/src/diskarray.jl:57 [inlined]
 [15] need_batch(a::NcVar{Float64, 1, 6}, i::Tuple{Vector{Int64}})
    @ DiskArrays ~/.julia/packages/DiskArrays/6JA8Z/src/diskarray.jl:54
 [16] getindex_disk!
    @ ~/.julia/packages/DiskArrays/6JA8Z/src/diskarray.jl:249 [inlined]
 [17] getindex_disk
    @ ~/.julia/packages/DiskArrays/6JA8Z/src/diskarray.jl:210 [inlined]
 [18] getindex
    @ ~/.julia/packages/DiskArrays/6JA8Z/src/diskarray.jl:348 [inlined]
 [19] (::var"#3#4")(ncv::NcVar{Float64, 1, 6})
    @ Main ~/.julia/dev/NCDatasets/test/test_empty.jl:11
 [20] open(::var"#3#4", ::String, ::Vararg{String}; kwargs::@Kwargs{})
    @ NetCDF ~/.julia/packages/NetCDF/BeMqn/src/NetCDF.jl:1000
 [21] open(::Function, ::String, ::String)
    @ NetCDF ~/.julia/packages/NetCDF/BeMqn/src/NetCDF.jl:997
 [22] top-level scope
    @ ~/.julia/dev/NCDatasets/test/test_empty.jl:10
 [23] include(fname::String)
    @ Base.MainInclude ./client.jl:489
 [24] top-level scope
    @ REPL[3]:1
in expression starting at /home/abarth/.julia/dev/NCDatasets/test/test_empty.jl:10
```

```
(@da04) pkg> status --manifest
Status `~/.julia/environments/da04/Manifest.toml`
  [179af706] CFTime v0.1.3
  [1fbeeb36] CommonDataModel v0.3.6
⌃ [34da2185] Compat v4.15.0
  [864edb3b] DataStructures v0.18.20
  [3c3547ce] DiskArrays v0.4.4
  [692b3bcd] JLLWrappers v1.5.0
  [8ac3fa9e] LRUCache v1.6.1
  [3da0fdf6] MPIPreferences v0.1.11
  [85f8d34a] NCDatasets v0.14.5 `~/.julia/dev/NCDatasets`
  [30363a11] NetCDF v0.12.0
  [6fe1bfb0] OffsetArrays v1.14.1
  [bac558e1] OrderedCollections v1.6.3
  [21216c6a] Preferences v1.4.3
  [0b7ba130] Blosc_jll v1.21.5+0
  [6e34b625] Bzip2_jll v1.0.8+1
  [0951126a] GnuTLS_jll v3.8.4+0
  [0234f1f7] HDF5_jll v1.14.3+3
  [e33a78d0] Hwloc_jll v2.11.1+0
  [94ce4f54] Libiconv_jll v1.17.0+0
  [5ced341a] Lz4_jll v1.10.0+0
  [7cb0a576] MPICH_jll v4.2.2+0
  [f1f71cc9] MPItrampoline_jll v5.4.0+0
  [9237b28f] MicrosoftMPI_jll v10.1.4+2
  [7243133f] NetCDF_jll v400.902.211+1
⌅ [4c82536e] Nettle_jll v3.7.2+0
⌅ [fe0851c0] OpenMPI_jll v4.1.6+0
  [458c3c95] OpenSSL_jll v3.0.14+0
  [c2071276] P11Kit_jll v0.24.1+0
⌃ [02c8fc9c] XML2_jll v2.13.1+0
  [ffd25f8a] XZ_jll v5.4.6+0
  [3161d3a3] Zstd_jll v1.5.6+0
  [477f73a3] libaec_jll v1.1.2+0
  [337d8026] libzip_jll v1.10.1+0
  [0dad84c5] ArgTools v1.1.1
  [56f22d72] Artifacts
  [2a0f44e3] Base64
  [ade2ca70] Dates
  [f43a241f] Downloads v1.6.0
  [7b1f6079] FileWatching
  [b77e0a4c] InteractiveUtils
  [4af54fe1] LazyArtifacts
  [b27032c2] LibCURL v0.6.4
  [76f85450] LibGit2
  [8f399da3] Libdl
  [37e2e46d] LinearAlgebra
  [56ddb016] Logging
  [d6f4376e] Markdown
  [ca575930] NetworkOptions v1.2.0
  [44cfe95a] Pkg v1.10.0
  [de0858da] Printf
  [3fa0cd96] REPL
  [9a3f8284] Random
  [ea8e919c] SHA v0.7.0
  [9e88b42a] Serialization
  [6462fe0b] Sockets
  [2f01184e] SparseArrays v1.10.0
  [10745b16] Statistics v1.10.0
  [fa267f1f] TOML v1.0.3
  [a4e569a6] Tar v1.10.0
  [cf7118a7] UUIDs
  [4ec0a83e] Unicode
  [e66e0078] CompilerSupportLibraries_jll v1.1.1+0
  [781609d7] GMP_jll v6.2.1+6
  [deac9b47] LibCURL_jll v8.4.0+0
  [e37daf67] LibGit2_jll v1.6.4+0
  [29816b5a] LibSSH2_jll v1.11.0+1
  [c8ffd9c3] MbedTLS_jll v2.28.2+1
  [14a3606d] MozillaCACerts_jll v2023.1.10
  [4536629a] OpenBLAS_jll v0.3.23+4
  [bea87d4a] SuiteSparse_jll v7.2.1+1
  [83775a58] Zlib_jll v1.2.13+1
  [8e850b90] libblastrampoline_jll v5.8.0+1
  [8e850ede] nghttp2_jll v1.52.0+1
  [3f19e933] p7zip_jll v17.4.0+2
Info Packages marked with ⌃ and ⌅ have new versions available. Those with ⌃ may be upgradable, but those with ⌅ are restricted by compatibility constraints from upgrading. To see why use `status --outdated -m`
```

Is this an already known issue?
Or is this not supported?
