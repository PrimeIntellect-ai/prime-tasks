BoundsError in MutableBinaryHeap delete!
If run with ```--check-bounds=yes```, the following throws ```BoundsError```:
```Julia
x = MutableBinaryMinHeap{Int}()
h1 = push!(x, 1)
h2 = push!(x, 2)
delete!(x, h2)
```
[Offending line](https://github.com/JuliaCollections/DataStructures.jl/blob/v0.17.13/src/heaps/mutable_binary_heap.jl#L116)
```Julia
        [HIDDEN]
```

Looks to happen when deleting from the end of the heap. The code is safe under the assumption that ```pop!(::Vector)``` doesn't resize underlying storage, but not ideal to have this throw when bounds checks are forced.

### Additional contract requirements

- Deleting the last element from a mutable binary heap must complete without a `BoundsError` when bounds checking is forced, and the remaining heap contents must be correct.
