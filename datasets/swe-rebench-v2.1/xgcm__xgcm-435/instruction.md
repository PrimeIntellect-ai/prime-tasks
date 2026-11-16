[BUG] Problems with custom grid ufunc and dask options
<!-- Please include a self-contained copy-pastable example that generates the issue if possible.

Please be concise with code posted. See guidelines below on how to provide a good bug report:

- Craft Minimal Bug Reports: http://matthewrocklin.com/blog/work/2018/02/28/minimal-bug-reports
- Minimal Complete Verifiable Examples: https://stackoverflow.com/help/mcve

Bug reports that follow these guidelines are easier to diagnose, and so are often handled much more quickly.
-->

**What happened**:
I was trying to check out how to write and apply custom grid_ufuncs and ran into an issue, that @TomNicholas and I concluded was actually a bug.

I start with a simple dataset, that is chunked, but not along any core dimensions. As such I expect `dask='parallelized'` to work as input.

```python
from xgcm.grid_ufunc import as_grid_ufunc
from xgcm.test.test_grid_ufunc import create_1d_test_grid_ds, create_1d_test_grid

ds = create_1d_test_grid_ds('X')
grid = create_1d_test_grid('X')
da = np.sin(grid._ds.X_c)
da = da.chunk({'X_c':-1})
da


# simple forward difference
@as_grid_ufunc(
    signature="(ax0:center)->(ax0:right)",
    boundary_width={"ax0": (1, 0)},
    dask='parallelized'
)
def test_ufunc(a):
    out = a[..., :-1] - a[..., 1:]
    return out

ufunc_diff = test_ufunc(grid, da, axis='X')
ufunc_diff
```

But this returns the following error:
```
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
/tmp/ipykernel_2409/2481888569.py in <module>
     19     return out
     20
---> 21 ufunc_diff = test_ufunc(grid, da, axis='X')
     22 ufunc_diff

~/xgcm/xgcm/grid_ufunc.py in __call__(self, grid, axis, *args, **kwargs)
    158         dask = kwargs.pop("dask", self.dask)
    159         map_overlap = kwargs.pop("map_overlap", self.map_overlap)
--> 160         return apply_as_grid_ufunc(
    161             self.ufunc,
    162             *args,

~/xgcm/xgcm/grid_ufunc.py in apply_as_grid_ufunc(func, axis, grid, signature, boundary_width, boundary, fill_value, keep_coords, dask, map_overlap, *args, **kwargs)
    477
    478     # Perform operation via xarray.apply_ufunc
--> 479     results = xr.apply_ufunc(
    480         mapped_func,
    481         *rechunked_padded_args,

/srv/conda/envs/notebook/lib/python3.8/site-packages/xarray/core/computation.py in apply_ufunc(func, input_core_dims, output_core_dims, exclude_dims, vectorize, join, dataset_join, dataset_fill_value, keep_attrs, kwargs, dask, output_dtypes, output_sizes, meta, dask_gufunc_kwargs, *args)
   1157     # feed DataArray apply_variable_ufunc through apply_dataarray_vfunc
   1158     elif any(isinstance(a, DataArray) for a in args):
-> 1159         return apply_dataarray_vfunc(
   1160             variables_vfunc,
   1161             *args,

/srv/conda/envs/notebook/lib/python3.8/site-packages/xarray/core/computation.py in apply_dataarray_vfunc(func, signature, join, exclude_dims, keep_attrs, *args)
    284
    285     data_vars = [getattr(a, "variable", a) for a in args]
--> 286     result_var = func(*data_vars)
    287
    288     if signature.num_outputs > 1:

/srv/conda/envs/notebook/lib/python3.8/site-packages/xarray/core/computation.py in apply_variable_ufunc(func, signature, exclude_dims, dask, output_dtypes, vectorize, keep_attrs, dask_gufunc_kwargs, *args)
    670                         for axis, dim in enumerate(core_dims, start=-len(core_dims)):
    671                             if len(data.chunks[axis]) != 1:
--> 672                                 raise ValueError(
    673                                     f"dimension {dim} on {n}th function argument to "
    674                                     "apply_ufunc with dask='parallelized' consists of "

ValueError: dimension X_c on 0th function argument to apply_ufunc with dask='parallelized' consists of multiple chunks, but is also a core dimension. To fix, either rechunk into a single dask array chunk along this dimension, i.e., ``.chunk(dict(X_c=-1))``, or pass ``allow_rechunk=True`` in ``dask_gufunc_kwargs`` but beware that this may significantly increase memory usage.
```

What seems to happen here is that the padding adds chunks along the core dimension `X_c`, [HIDDEN]

[HIDDEN]

### Additional contract requirements

- For a custom grid ufunc using `dask='parallelized'`, applying boundary padding to Dask-backed input whose core dimension is initially a single chunk must succeed and produce the result defined by the ufunc.
