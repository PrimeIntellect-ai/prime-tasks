Allow Spline to take a region argument
Right now, `verde.Spline` uses the data region to create a regular grid of forces (if `spacing` is provided). The problem with this is that the model will change between runs of a kfold cross-validation because the data changed. A way around that is allow `Spline` to take a `region` argument that fixes this region.

Simply checking if the data region already exists is not good because there is the implicit assumption that it is set to the first data-set that we fitted. And there is no way to change that via `set_params`. Having an explicit parameter is better.

### Additional contract requirements

- `verde.Spline` must accept an optional `region` argument in its constructor: `Spline(fudge=1e-5, damping=None, shape=None, spacing=None, region=None)`.
- When a `region` is supplied, the regular grid of forces (used when `shape` or `spacing` is set) must be generated over that region, so the force coordinates span the given bounds.
- When no `region` is supplied, the region used for the regular grid of forces is taken from the data of the first fit and must stay the same for any later fit.

- The explicit region can be changed through the estimator’s standard `set_params` interface, and a subsequent fit must generate the regular force grid over the updated bounds.
