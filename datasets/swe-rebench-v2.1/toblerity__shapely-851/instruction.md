Polylabel bug
## Expected behavior and actual behavior.

Holes are not correctly accounted for in shapely's implementation of the polylabel algorithm.

## Steps to reproduce the problem.

```
from shapely.geometry import Polygon
from shapely.algorithms.polylabel import polylabel
poly1=Polygon(shell=[(0,0),(10,0),(10,10),(0,10),(0,0)][::-1], holes=[[(2,2),(6,2),(6,6),(2,6),(2,2)]])
import geopandas
gdf2 = geopandas.GeoDataFrame(geometry=[poly1])
gdf2.plot()
label_location = polylabel(poly1, tolerance=0.05)
print(label_location.x)
print(label_location.y)
```

The output of this script is:

```
6.25
3.75
```

But the correct position is something close to 7.65625, 7.65625. This can be verified by looking at a plot of this polygon

![image](https://user-images.githubusercontent.com/30300995/71988175-663d4600-31fd-11ea-9bbb-6f849f9f34a6.png)

Maybe I am doing something wrong in the definition of the polygon but I have tried many different ways of instantiating this polygon and I always get the same result.

## Operating system

Linux

## Shapely version and provenance

Tested with shapely version 1.6 and 1.7a3

### Additional contract requirements

- For the polygon in this example with tolerance 0.05, the returned location's x and y coordinates must each satisfy Python's default `unittest.TestCase.assertAlmostEqual` comparison against `7.65625`.
