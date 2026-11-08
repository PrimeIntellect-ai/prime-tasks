Voxelwise dvars explodes with voxels with variance ~1e-19
### Summary

In `compute_dvars` we remove zero-variance voxels:

https://github.com/nipy/nipype/blob/3e7e61339ee7d0e67c917477fa989759fa69a577/nipype/algorithms/confounds.py#L1045-L1054

However, if `func_sd` is small but nonzero, this will propagate to `diff_sdhat`:

https://github.com/nipy/nipype/blob/3e7e61339ee7d0e67c917477fa989759fa69a577/nipype/algorithms/confounds.py#L1061-L1063

Which then can explode the values in

https://github.com/nipy/nipype/blob/3e7e61339ee7d0e67c917477fa989759fa69a577/nipype/algorithms/confounds.py#L1078-L1080

If sufficiently small, we will overflow `float32`.

### Proposal

We should set a default threshold for "zerovariance". I think 1e-10 is more than small enough. In the example dataset I have, only one additional voxel is caught by this less stringent threshold, and would avoid the failure.

Will propose a fix soon, but wanted to give people a chance to comment.

### Additional contract requirements

- `nipype.algorithms.confounds.compute_dvars` accepts a `variance_tol` keyword argument (float, default `0.0`). When `remove_zerovariance` is true, only voxels whose variance is greater than `variance_tol` are retained for the computation.
- The `ComputeDVARS` interface exposes a `variance_tol` input (float) with default `1e-7`.
- A tolerance supplied to `ComputeDVARS` is used when its computation determines which voxels to retain.
