Add map_overlap as a new core op
It would be nice to add `map_overlap` alongside `map_blocks`, `blockwise`, `rechunk`, and `apply_gufunc`.

It's currently not directly used within xarray (even within `xarray.map_blocks`, which builds a HLG), but maybe it could / should be used there (cc @dcherian)

Regardless I think it should be on the wishlist as it is used in some other packages. For example `xgcm.apply_as_grid_ufunc` uses a [pattern where `dask.array.map_overlap` is called](https://github.com/xgcm/xgcm/blob/f4adb05fab54a852ad3db0ff0354d70c24601323/xgcm/grid_ufunc.py#LL973C2-L973C2) from within the function supplied to `xarray.apply_ufunc()`, (it wraps the actual numpy function, so the kwarg is `dask='allowed'`). This is a trick that allows parallelism along all dimensions (both core dims and broadcast dims) for a large class of array algorithms of interest (e.g. differential functions).

`dask.map_overlap` is mostly implemented using `map_blocks`.

### Additional contract requirements

- Add a public function `map_overlap(func, *args, dtype=None, chunks=None, depth=None, boundary=None, trim=False, **kwargs)` in module `cubed.overlap`, also available as `cubed.map_overlap`.
- `depth` accepts an int, a tuple, a list, or a dict.
- `boundary` accepts a constant value, a tuple, or a dict.
- Additional keyword arguments are passed through to `func`.
- Passing `trim=True` raises `ValueError`.
