copyto! fails when one of the axes has a zero length index
Using copyto! with a zero length axis breaks with a DiskArray but succeeds with a normal Array.
This breaks the show method of DimArrays with a DiskArray in some circumstances see https://github.com/rafaqz/DimensionalData.jl/issues/670.


```julia
    a = collect(reshape(1:90, 10, 9))
    a_disk = AccessCountDiskArray(a; chunksize=(5, 3))
        x_empty = Matrix{Int64}(undef, 0,2)
        copyto!(x_empty, CartesianIndices((1:0, 1:2)), a_disk, CartesianIndices((8:7, 8:9))) # This fails
        copyto!(x_empty, CartesianIndices((1:0, 1:2)), a, CartesianIndices((8:7, 8:9))) # This works
```

### Additional contract requirements

- When the destination and source regions passed to `copyto!` have different sizes, it must throw an `ArgumentError`.
