Weird behavior with cumsum
I've been trying to take the cummulative sum using `xgcm.cumsum()` but I'm getting a weird behavior when the data is not loaded. I've added a reproducible example below.

```
ds = xr.DataArray(np.ones(10)*.5,dims='Z',coords={'Z':np.arange(.5,10,1)}).chunk({'Z':-1}).to_dataset(name='drF')
ds.coords['Zp1'] = xr.DataArray(np.arange(11),dims='Zp1',coords={'Zp1':np.arange(11)})
grid = Grid(ds, coords={'Z': {'center': 'Z', 'outer': 'Zp1'}})

grid.cumsum(ds.drF, 'Z', boundary='extend')
---------------------------------------------------------------------------
KeyError                                  Traceback (most recent call last)
Input In [55], in <cell line: 1>()
----> 1 grid.cumsum(ds.drF, 'Z', boundary='extend')

File ~/miniconda3/envs/xgcm/lib/python3.9/site-packages/xgcm/grid.py:2245, in Grid.cumsum(self, da, axis, **kwargs)
   2196 def cumsum(self, da, axis, **kwargs):
   2197     """
   2198     Cumulatively sum a DataArray, transforming to the intermediate axis
   2199     position.
   (...)
   2243     >>> grid.max(da, ["X", "Y"], fill_value={"X": 0, "Y": 100})
   2244     """
-> 2245     return self._1d_grid_ufunc_dispatch("cumsum", da, axis, **kwargs)

File ~/miniconda3/envs/xgcm/lib/python3.9/site-packages/xgcm/grid.py:1831, in Grid._1d_grid_ufunc_dispatch(self, funcname, data, axis, to, keep_coords, metric_weighted, other_component, **kwargs)
   1828 else:
   1829     map_overlap = False
-> 1831 array = grid_ufunc(
   1832     self,
   1833     array,
   1834     axis=[(ax_name,)],
   1835     keep_coords=keep_coords,
   1836     dask=dask,
   1837     map_overlap=map_overlap,
   1838     other_component=other_component,
   1839     **remaining_kwargs,
   1840 )
   1842 if ax_metric_weighted:
   1843     metric = self.get_metric(array, ax_metric_weighted)

File ~/miniconda3/envs/xgcm/lib/python3.9/site-packages/xgcm/grid_ufunc.py:460, in GridUFunc.__call__(self, grid, axis, *args, **kwargs)
    458 map_overlap = kwargs.pop("map_overlap", self.map_overlap)
    459 pad_before_func = kwargs.pop("pad_before_func", self.pad_before_func)
--> 460 return apply_as_grid_ufunc(
    461     self.ufunc,
    462     *args,
    463     axis=axis,
    464     grid=grid,
    465     signature=self.signature,
    466     boundary_width=self.boundary_width,
    467     boundary=boundary,
    468     dask=dask,
    469     map_overlap=map_overlap,
    470     pad_before_func=pad_before_func,
    471     **kwargs,
    472 )

File ~/miniconda3/envs/xgcm/lib/python3.9/site-packages/xgcm/grid_ufunc.py:791, in apply_as_grid_ufunc(func, axis, grid, signature, boundary_width, boundary, fill_value, keep_coords, dask, map_overlap, pad_before_func, other_component, *args, **kwargs)
    780 else:  # pad after func
    781     unpadded_results = _apply(
    782         mapped_func,
    783         args,
   (...)
    789         **kwargs,
    790     )
--> 791     results = _pad_then_rechunk(
    792         unpadded_results,
    793         grid,
    794         in_core_dims,
    795         boundary_width_real_axes,
    796         boundary,
    797         fill_value,
    798         other_component,
    799     )
    801 # TODO add option to trim result if not done in ufunc
    802 # TODO loud warning if ufunc returns array of incorrect size
    803
    804 # Restore any dimension coordinates associated with new output dims that are present in grid
    805 results_with_coords = _reattach_coords(results, grid, boundary_width, keep_coords)

File ~/miniconda3/envs/xgcm/lib/python3.9/site-packages/xgcm/grid_ufunc.py:893, in _pad_then_rechunk(args, grid, in_core_dims, boundary_width_real_axes, boundary, fill_value, other_component)
    871 def _pad_then_rechunk(
    872     args,
    873     grid,
   (...)
    878     other_component,
    879 ):
    881     padded_args = [
    882         pad(
    883             a,
   (...)
    890         for a, oc in zip(args, other_component)
    891     ]
--> 893     if any(
    894         _has_chunked_core_dims(padded_arg, core_dims)
    895         for padded_arg, core_dims in zip(padded_args, in_core_dims)
    896     ):
    897         # merge any lonely chunks on either end created by padding
    898         rechunked_padded_args = _rechunk_to_merge_in_boundary_chunks(
    899             padded_args,
    900             args,
    901             boundary_width_real_axes,
    902             grid,
    903         )
    904     else:

File ~/miniconda3/envs/xgcm/lib/python3.9/site-packages/xgcm/grid_ufunc.py:894, in <genexpr>(.0)
    871 def _pad_then_rechunk(
    872     args,
    873     grid,
   (...)
    878     other_component,
    879 ):
    881     padded_args = [
    882         pad(
    883             a,
   (...)
    890         for a, oc in zip(args, other_component)
    891     ]
    893     if any(
--> 894         _has_chunked_core_dims(padded_arg, core_dims)
    895         for padded_arg, core_dims in zip(padded_args, in_core_dims)
    896     ):
    897         # merge any lonely chunks on either end created by padding
    898         rechunked_padded_args = _rechunk_to_merge_in_boundary_chunks(
    899             padded_args,
    900             args,
    901             boundary_width_real_axes,
    902             grid,
    903         )
    904     else:

File ~/miniconda3/envs/xgcm/lib/python3.9/site-packages/xgcm/grid_ufunc.py:917, in _has_chunked_core_dims(obj, core_dims)
    915 def _has_chunked_core_dims(obj: xr.DataArray, core_dims: Sequence[str]) -> bool:
    916     # TODO what if only some of the core dimensions are chunked?
--> 917     return obj.chunks is not None and any(
    918         _is_dim_chunked(obj, dim) for dim in core_dims
    919     )

File ~/miniconda3/envs/xgcm/lib/python3.9/site-packages/xgcm/grid_ufunc.py:918, in <genexpr>(.0)
    915 def _has_chunked_core_dims(obj: xr.DataArray, core_dims: Sequence[str]) -> bool:
    916     # TODO what if only some of the core dimensions are chunked?
    917     return obj.chunks is not None and any(
--> 918         _is_dim_chunked(obj, dim) for dim in core_dims
    919     )

[HIDDEN]
    910 def _is_dim_chunked(a, dim):
    911     # TODO this func can't handle Datasets - it will error if you check multiple variables with different chunking
[HIDDEN]

File ~/miniconda3/envs/xgcm/lib/python3.9/site-packages/xarray/core/utils.py:457, in Frozen.__getitem__(self, key)
    456 def __getitem__(self, key: K) -> V:
--> 457     return self.mapping[key]

KeyError: 'Z'
```

The error goes away when I load the data, i.e.
```
grid.cumsum(ds.drF.load(), 'Z', boundary='extend')
```

**xgcm version and environment**:
My xgcm version is 0.7.0.

### Additional contract requirements

- Calling `grid.cumsum` on Dask-chunked data, including the reported `boundary='extend'` case, must work without requiring the data to be loaded first and return a cumulative sum rather than raising `KeyError`.
