Mixed indexing fail. a[CartesianIndex(1, 2), 1:end]
Missing CartesianIndex with a range gives an error.


```julia
using DiskArrays: ReshapedDiskArray, PermutedDiskArray
using DiskArrays.TestTypes
data = reshape(1:24, 2, 3, 4)
a = AccessCountDiskArray(data, chunksize=(2, 2, 2))

a[CartesianIndex(1, 2), 1:end] # gives an error
data[CartesianIndex(1, 2), 1:end] # works fine
```
