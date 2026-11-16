negative size shape is allowed
I noticed that values of `shape` can be negative, this doesn't seem desirable, it has the effect of flipping the transform as expected.

```python
from odc.geo.geobox import GeoBox
ex = [-120, -100, 35, 55]

g = GeoBox.from_bbox([140, -43, 160, -23],
   "EPSG:4326",
   shape = [-1, 1])
g
#GeoBox((-1, 1), Affine(20.0, 0.0, 140.0,
#       0.0, 20.0, -60.0), CRS('EPSG:4326'))
```

I only noticed because I wanted to do the GDAL thing of setting one of the dimensions to zero, whereby you only need to use the shape of one side and it helpfully calculates the other from the aspect ratio of the extent. This is nice because it gives a very short heuristic for "about this detailed" that matches how images work, rather than having  to specify a specific resolution or do gymnastics to work out the ratio.

So, maybe negative shape should be disallowed, and if it's of interest I could PR the `shape = [0, n]` or `shape = [n, 0]`.

Thanks!

### Additional contract requirements

A GeoBox must reject a shape if either dimension is negative, whether it is created directly or with `GeoBox.from_bbox`. The specific exception type is not prescribed.
