Check if values passed in `coords={..}` are valid dimensions.
Currently xgcm does not check if the values passed in `Grid(..., coords={...})` are valid dimensions upon the creation of the grid object.

I recently came across a situation like this:
```python
import xarray as xr
import numpy as np
data = np.random.rand(4,5)
coord = np.random.rand(4,5)
ds = xr.DataArray(data, dims=['x','y'], coords={'c':(['x', 'y'], coord)}).to_dataset(name='data')
```

Should it be possible to assign a coordinate instead of a dimension like this:
```python
from xgcm import Grid
grid = Grid(ds, coords={'X':{'center':'c'}})
```
this currently does not raise an error/warning.

Only when trying to compute something we get:
```python
grid.diff(ds.data,'X')
```

```
...
KeyError: "None of the DataArray's dims ('x', 'y') were found in axis coords."
```

I think it might be easier for new users to get a warning like ` c is not a dataset dimension. xgcm can only accept 1D dimensions in coords` or similar. Should be very cheap test too, so not weigh the grid object creation down too much.

cc @abigalew
