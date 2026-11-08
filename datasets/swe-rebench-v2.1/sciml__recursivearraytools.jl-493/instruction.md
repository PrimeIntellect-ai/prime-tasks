Bug: `recursivefill!` fails on `VectorOfArray` with mixed immutable and mutable StaticArrays
**Description**

The `recursivefill!` function fails with a `setindex!` error when used on a `VectorOfArray` that contains a mix of immutable and mutable `StaticArray` types (e.g., `SVector` and `MVector`).

The function attempts to fill all subarrays in-place. This works for mutable types like `MVector`, but it fails for immutable types like `SVector`, which cannot be modified after creation.

This appears to be a bug in the `Base.fill!` implementation for `AbstractVectorOfArray` in `src/vector_of_array.jl`, which does not check for immutability before attempting to modify the arrays.

@ChrisRackauckas
