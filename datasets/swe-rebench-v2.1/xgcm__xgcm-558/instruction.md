Error when interpolating `to='outer'`
This is pigging back on the issue #507 but using the version `xgcm=0.8.0` now I'm getting an error when trying to interpolate along a dimension that has `outer` coordinates. I've pasted a reproducible example below.

```
ds = xr.DataArray(np.ones(10)*.5,dims='Z',coords={'Z':np.arange(.5,10,1)}).chunk({'Z':-1}).to_dataset(name='drF')
ds.coords['Zp1'] = xr.DataArray(np.arange(11),dims='Zp1',coords={'Zp1':np.arange(11)})
grid = Grid(ds, coords={'Z': {'center': 'Z', 'outer': 'Zp1'}})

grid.interp(ds.drF, 'Z', boundary='extend', to='outer')

--------------------------------------------------------------------
NotImplementedError                       Traceback (most recent call last)
Input In [19], in <cell line: 5>()
      2 ds.coords['Zp1'] = xr.DataArray(np.arange(11),dims='Zp1',coords={'Zp1':np.arange(11)})
      3 grid = Grid(ds, coords={'Z': {'center': 'Z', 'outer': 'Zp1'}})
----> 5 grid.interp(ds.drF, 'Z', boundary='extend', to='outer')

File ~/miniconda3/envs/xgcm/lib/python3.9/site-packages/xgcm/grid.py:2041, in Grid.interp(self, da, axis, **kwargs)
   1989 def interp(self, da, axis, **kwargs):
   1990     """
   1991     Interpolate neighboring points to the intermediate grid point along
   1992     this axis.
   (...)
   2039     >>> grid.interp(da, ["X", "Y"], periodic={"X": True, "Y": False})
   2040     """
-> 2041     return self._1d_grid_ufunc_dispatch("interp", da, axis, **kwargs)

File ~/miniconda3/envs/xgcm/lib/python3.9/site-packages/xgcm/grid.py:1836, in Grid._1d_grid_ufunc_dispatch(self, funcname, data, axis, to, keep_coords, metric_weighted, other_component, **kwargs)
   1833 else:
   1834     map_overlap = False
-> 1836 array = grid_ufunc(
   1837     self,
   1838     array,
   1839     axis=[(ax_name,)],
   1840     keep_coords=keep_coords,
   1841     dask=dask,
   1842     map_overlap=map_overlap,
   1843     other_component=other_component,
   1844     **remaining_kwargs,
   1845 )
   1847 if ax_metric_weighted:
   1848     metric = self.get_metric(array, ax_metric_weighted)

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

File ~/miniconda3/envs/xgcm/lib/python3.9/site-packages/xgcm/grid_ufunc.py:745, in apply_as_grid_ufunc(func, axis, grid, signature, boundary_width, boundary, fill_value, keep_coords, dask, map_overlap, pad_before_func, other_component, *args, **kwargs)
    742 # Maybe map function over chunked core dims using dask.array.map_overlap
    743 if map_overlap:
    744     # Disallow situations where shifting axis position would cause chunk size to change
--> 745     _check_if_length_would_change(sig)
    747     mapped_func = _map_func_over_core_dims(
    748         func,
    749         args,
   (...)
    753         out_dtypes,
    754     )
    755 else:

File ~/miniconda3/envs/xgcm/lib/python3.9/site-packages/xgcm/grid_ufunc.py:1002, in _check_if_length_would_change(signature)
    996 all_ax_positions = set(
    997     p
    998     for arg_ps in signature.in_ax_positions + signature.out_ax_positions
    999     for p in arg_ps
   1000 )
   1001 if any(pos in DISALLOWED_OVERLAP_POSITIONS for pos in all_ax_positions):
-> 1002     raise NotImplementedError(
   1003         "Cannot chunk along a core dimension for a grid ufunc which has a signature which "
   1004         f"includes one of the axis positions {DISALLOWED_OVERLAP_POSITIONS}"
   1005     )

NotImplementedError: Cannot chunk along a core dimension for a grid ufunc which has a signature which includes one of the axis positions ['inner', 'outer']
```

The error goes away again if I load the array into memory:

`grid.interp(ds.drF.load(), 'Z', boundary='extend', to='outer')`
