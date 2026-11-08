Default CPU workgroupsize can be inadequat for higher-dimensionsal kernels
As observed in https://github.com/WaterLily-jl/WaterLily.jl/pull/133#issuecomment-2263500896

When we have a grid like `(64, 64, 64)` using a WG size of (1024, 1, 1) is inefficient. Instead WL uses `(64,1,1)` and maybe KA should "spread" the `1024` to `(64, 64,1)`.

### Additional contract requirements

When the CPU backend selects a workgroup automatically for a multidimensional iteration space, it should distribute work across dimensions where their sizes permit, rather than concentrating the workgroup in one dimension. For a CPU launch over a `(64, 64, 64)` iteration space, workgroups should cover multiple iterations along at least two dimensions.
