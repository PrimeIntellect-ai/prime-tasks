CV: edge case in landmass, AOI intersection
This turned up here: https://community.naturalcapitalproject.org/t/coastal-vulnerability-typeerror-cannot-unpack-non-iterable-nonetype-object/2949/7

```
2022-07-27 11:11:13,542 (natcap.invest.utils) utils.prepare_workspace(167) ERROR Exception while executing natcap.invest.coastal_vulnerability
Traceback (most recent call last):
File “natcap\invest\utils.py”, line 165, in prepare_workspace
File “natcap\invest\cli.py”, line 486, in main
File “natcap\invest\coastal_vulnerability.py”, line 476, in execute
File “taskgraph\Task.py”, line 674, in add_task
File “taskgraph\Task.py”, line 1093, in _call
File “natcap\invest\coastal_vulnerability.py”, line 807, in prepare_landmass_line_index_and_interpolate_shore_points
File “shapely\ops.py”, line 113, in linemerge
File “shapely\geometry\multilinestring.py”, line 49, in init
File “shapely\geometry\multilinestring.py”, line 141, in geos_multilinestring_from_py
TypeError: cannot unpack non-iterable NoneType object
```

In this case the landmass polygon has two vertices that are basically identical. The model converts the polygons to lines and then intersects each line with the AOI polygon. We end up trying to intersect a polygon with a line where the start and end coordinate pairs are the same, like this:

```python
from shapely.geometry import Point, LineString
polygon = Point(0, 0).buffer(2)
polygon.intersection(LineString([(1, 1), (1, 1)]))
```

This returns an object of the expected type `shapely.geometry.linestring.LineString`, but it's `coords` property is an empty sequence.

The `LineString` from the user's data has these coordinates, but the return value from the intersection is the same as the simple example above.
```
(420275.798461657,  6042939.285698998)
(420275.7984616568, 6042939.285698998)
```

We actually already try to guard against a `LineString` like this in CV, probably because duplicate vertices are not that uncommon in GIS data. But in this case [HIDDEN]
