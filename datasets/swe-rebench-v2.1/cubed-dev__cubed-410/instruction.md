Removing `numpy.array_api` import
Hi, I noticed through code search that there are a few comments in this repo that reference `numpy.array_api` and (more importantly) one import:

https://github.com/cubed-dev/cubed/blob/76ea07e6301c53202b990442677e1c82da5e2a3a/cubed/array_api/data_type_functions.py#L4

I wanted to give you a heads up that in NumPy 2.0 that import will break. Because we'll have support for the array API standard in the main `numpy` namespace, the `numpy.array_api` submodule is being removed (see https://github.com/numpy/numpy/pull/25911).

For testing purposes, https://github.com/data-apis/array-api-strict can be used. [HIDDEN]

### Additional contract requirements

- `cubed.array_api.finfo(type)` returns an object mirroring NumPy's `finfo`, exposing the attributes `bits` (int), `eps`, `max`, `min`, `smallest_normal` (floating-point values), and `dtype` (the dtype passed in).
- `cubed.backend_array_api.namespace.unique_values(x)` returns a one-dimensional backend array containing the unique values present in `x`.
- A top-level `import cubed` must succeed when `numpy.array_api` is unavailable.
