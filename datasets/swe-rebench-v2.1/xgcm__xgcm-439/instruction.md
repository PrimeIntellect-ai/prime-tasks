[BUG] xgcm cant detect proper ufunc for chunked data.


**What happened**:
I just tested the new grid_ufunc branch and ran into an issue when working with chunked datasets.

**What you expected to happen**:
I expected the 'basic' grid methods like diff to work on datasets of really any chunking structure, especially when chunked along non-core dimensions

**Minimal Complete Verifiable Example**:
But when I try this:
```python
from xgcm import Grid
from xgcm.test.datasets import datasets_grid_metric
ds, coords, metrics = datasets_grid_metric('C')
ds = ds.chunk({'time':1})
grid = Grid(ds, coords=coords)
grid.diff(ds.tracer, 'X')
```
I get an error from the dispatching logic:
```
---------------------------------------------------------------------------
NotImplementedError                       Traceback (most recent call last)
/tmp/ipykernel_2409/1917141936.py in <module>
      5 ds = ds.chunk({'time':1})
      6 grid = Grid(ds, coords=coords)
----> 7 grid.diff(ds.tracer, 'X')

~/xgcm/xgcm/grid.py in diff(self, da, axis, **kwargs)
   1960         >>> grid.diff(da, ["X", "Y"], fill_value={"X": 0, "Y": 100})
   1961         """
-> 1962         return self._1d_grid_ufunc_dispatch("diff", da, axis, **kwargs)
   1963
   1964     @docstrings.dedent

~/xgcm/xgcm/grid.py in _1d_grid_ufunc_dispatch(self, funcname, da, axis, to, keep_coords, metric_weighted, **kwargs)
   1767         for signature_1d, ax_name in zip(signatures, axis):
   1768
-> 1769             grid_ufunc, remaining_kwargs = _select_grid_ufunc(
   1770                 funcname, signature_1d, module=gridops, **kwargs
   1771             )

~/xgcm/xgcm/grid.py in _select_grid_ufunc(funcname, signature, module, **kwargs)
   2336     ]
   2337     if len(name_matching_ufuncs) == 0:
-> 2338         raise NotImplementedError(
   2339             f"Could not find any pre-defined {funcname} grid ufuncs"
   2340         )

NotImplementedError: Could not find any pre-defined diff grid ufuncs
```
