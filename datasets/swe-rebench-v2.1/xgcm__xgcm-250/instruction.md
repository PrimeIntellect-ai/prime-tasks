Globally set `fill_value` set on grid object is not propagated.
I just discovered what I think is a bug:

Consider this simple example:
```
from xgcm import Grid
import xarray as xr
import numpy as np

z = np.arange(3)
z_right = z+0.5
ds = xr.DataArray(np.ones_like(z)*1e5, dims=['z'], coords={'z':z}).to_dataset(name='data')
ds = ds.assign_coords({'z_right':z_right})

grid = Grid(ds, coords={'Z':{'center':'z', 'right':'z_right'}},
            boundary='fill', fill_value=np.nan, periodic=False)
grid.interp(ds.data, 'Z')
```
This results in:

![image](https://user-images.githubusercontent.com/14314623/92794864-f24fd080-f37d-11ea-85cf-485dd378c971.jpeg)

Which is not what I would expect (the edge value should be padded with nan) and is not equivalent to the 'old-school' manual way:
```
grid.interp(ds.data, 'Z',boundary='fill', fill_value=np.nan)
```
![image](https://user-images.githubusercontent.com/14314623/92795073-190e0700-f37e-11ea-90b1-0ae3ba25de54.jpeg)

[HIDDEN]


We should add a test that checks that results are the same if you specify `boundary` and/or `fill_value` via grid object or in the axis method.

Pinging @dcherian

### Additional contract requirements

- When a grid-level `boundary` or `fill_value` is configured, an axis operation that omits the corresponding local option must behave as if that grid-level value were passed to the operation. In the example, `grid.interp(ds.data, 'Z')` must pad the edge with NaN when the grid is configured with `boundary='fill'` and `fill_value=np.nan`.
