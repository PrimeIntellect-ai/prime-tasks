BUG: Unexpected behavior in Overlay with keep_geom_type since Version 1.0.0
- [x] I have checked that this issue has not already been reported.

- [x] I have confirmed this bug exists on the latest version of geopandas.

- [x] (optional) I have confirmed this bug exists on the main branch of geopandas.

---

#### Code Sample

```python
import geopandas
from shapely import Polygon

invalid_polygon = Polygon([(0, 0), (1, 1), (1, 2), (1, 1), (0, 0)])
square = Polygon(((0,0),(1,0),(1,1),(0,1),(0,0)))
df1 = geopandas.GeoDataFrame({'A':[1,2]}, geometry=[invalid_polygon, square])
df2 = geopandas.GeoDataFrame({'B':[5,6]}, geometry=[square, square])

print(df1.geom_type[0])
print(df2.geom_type[0])
df1_df2 = df1.overlay(df2, keep_geom_type=True)
print(df1_df2.geom_type[0])

```

#### Problem description
Overlay switches the geometry type of the resulting GeoDataFrame entirely. The argument 'keep_geom_type=True' should keep the geometry type of the Geodataframe as Polygon, but in the example above, it changes it completely to Linestring. This Problem occurs since version 1.0.0, when overlay switched from buffer(0) to make_valid (make_valid does change the geometry type of the invalid Polygon, but buffer(0) does not). This results the first geometry of df1 to be of type Linestring, which seems to cause the behavior.

#### Expected Output
df1_df2 should have same geometry type as df1.
