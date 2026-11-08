Swap the order of dims and dtype in Coord[...] and Data[...]
Swap the order of dims and dtype s.t. ``Coord[dims, dtype]`` and ``Data[dims, dtype]``.
This is because their order in the printed format is (dims, dtype, value).

```
<xarray.DataArray (x: 3, y: 3)>
array([[0., 0., 0.],
       [0., 0., 0.],
       [0., 0., 0.]])
Coordinates:
  * x        (x) int64 0 0 0
  * y        (y) int64 0 0 0
```
