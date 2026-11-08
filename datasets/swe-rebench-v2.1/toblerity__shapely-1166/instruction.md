How to use strtree to find an element nearest to it but not its own?
## Expected behavior and actual behavior.


How to use strtree to find an element nearest to it but not its own?My code is as follows, what I expect to find is (1,1), not (0,0).
If I want to start from (0,0), find the nearest point (1,1), and then find the second nearest point (2,2), how do I operate?

## Steps to reproduce the problem.

from shapely.strtree import STRtree
from shapely.geometry import Point

points=[Point(0,0),Point(1,1),Point(2,2)]

tree=STRtree(points)

pos=tree.nearest(Point(0,0))
print(pos)

#POINT (0 0)

## Operating system

windows 10    20H2
python3.7.0 64-bit (conda)

## Shapely version and provenance

Shapely-1.7.1 from pip install

### Additional contract requirements

- `STRtree.nearest(geom, exclusive=True)` must be accepted. When `geom` is also one of the geometries stored in the tree, the call returns the nearest stored geometry other than `geom` itself, so the query geometry is never returned in that mode.
- With the default `exclusive=False`, `STRtree.nearest(geom)` behaves as before and returns the nearest stored geometry, including `geom` itself when it is stored.
- A caller can therefore find the nearest geometry to a stored point and then, after removing that result from a new tree, query the same origin again to obtain the second distinct nearest geometry.
