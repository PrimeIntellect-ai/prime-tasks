Coordinates __getitem__, slicing bug
## Description

Slicing of coordinates changes the original object instead of returning a new object.

## What I Did

```
import pyfar
coords = pyfar.Coordinates([0,1], [0,1], [0,1])
coords_sliced = coords[0]
coords.cshape == (2,)
```
