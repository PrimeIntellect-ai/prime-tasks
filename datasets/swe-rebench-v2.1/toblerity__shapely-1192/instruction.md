shapely.geometry.shape does not work with LinearRing
Shapely 1.7.1, Python 3.9.6 on mac

The `shape` function knows how to process Polygons but not LinearRings. So I need to convert my LinearRing into a Polygon to use it with certain libraries that attempt to work with various geometry types by using `shape`.

To remedy, the `shape` function should be taught about LinearRing.

```python

>>> from shapely.geometry import LinearRing, shape, Polygon
>>> l = LinearRing([(0,0), (0,1), (1,0)])
>>> p = Polygon([(0,0), (0,1), (1,0)])
>>> shape(p)
<shapely.geometry.polygon.Polygon object at 0x1032e2b80>
>>> shape(l)
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File ".venv/lib/python3.9/site-packages/shapely/geometry/geo.py", line 116, in shape
    raise ValueError("Unknown geometry type: %s" % geom_type)
ValueError: Unknown geometry type: linearring
```
