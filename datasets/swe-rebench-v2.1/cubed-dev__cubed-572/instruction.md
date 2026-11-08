Zarr compression settings for local intermediate files
When running [some benchmarks](https://github.com/cubed-dev/cubed/issues/492#issuecomment-2238908343) recently I noticed that turning off Zarr compression resulted in faster IO performance when writing random data to Zarr files on a local SSD. This [post](https://medium.com/@lubonjaariel/to-compress-or-not-to-compress-a-zarr-question-812160b3777d) seems to confirm that.

So perhaps we should turn off compression for intermediate Zarr data stored on the local filesystem.

### Additional contract requirements

For local intermediate Zarr data, users can explicitly disable compression by passing `zarr_compressor=None` when creating a `cubed.Spec`. When a computation is configured this way, its intermediate Zarr arrays are stored uncompressed. If no compressor choice is made, the Zarr library's default compressor remains in effect.
