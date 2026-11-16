Polygon build failure in Overlay difference
Given input:

```
A: POLYGON ((0 0, 4 0, 4 4, 0 4, 0 0), (1 1, 1 2, 2 1, 1 1), (1 2, 1 3, 2 3, 1 2), (2 3, 3 3, 3 2, 2 3))
B: POLYGON ((2 1, 3 1, 3 2, 2 1))
```

A.difference(B) returns an incorrect, invalid geometry.

The expected result is:

`POLYGON ((0 0, 4 0, 4 4, 0 4, 0 0), (1 1, 1 2, 2 1, 1 1), (1 2, 1 3, 2 3, 1 2), (2 3, 3 3, 3 2, 2 3), (2 1, 3 1, 3 2, 2 1))`

This was originally reported as https://trac.osgeo.org/geos/ticket/789

This is likely due to a logic error in the polygon building phase of overlay

### Additional contract requirements

- `A.difference(B)` must return a valid geometry covering the same region as the polygon above. The exact expected result is `MULTIPOLYGON (((0 0, 0 4, 4 4, 4 0, 0 0), (1 2, 1 1, 2 1, 3 1, 3 2, 3 3, 2 3, 1 3, 1 2)), ((2 1, 1 2, 2 3, 3 2, 2 1)))`.
