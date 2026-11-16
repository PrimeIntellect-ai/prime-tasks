Don't materialize `full` or offsets arrays
Arrays whose values are a function of the index do not need to be materialized - either in memory or on disk. These include arrays where every entry is the same (created with `full`), and arrays of offsets (used in `map_blocks` to provide block IDs to the map function).

Zarr arrays created with `full` are not expensive to create since they specify `write_empty_chunks=False` so no chunks are written - just the metadata. However, offsets are materialized to disk: https://github.com/tomwhite/cubed/blob/e21786591d9832a85f2e492641ad2061bdb8c14a/cubed/core/ops.py#L431-L432

Although the array is small since its size is the number of chunks, there is a scalability issue due to the fact that every chunk is stored in a separate file in the Zarr store.

[HIDDEN]
