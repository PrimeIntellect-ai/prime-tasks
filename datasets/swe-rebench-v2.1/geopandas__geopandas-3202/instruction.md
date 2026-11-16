API: polygonize and build_area as methods
As part of #2010, we want to expose functions as `polygonize` and `build_area`. Unlike for some other methods, it is not immediately clear what the GeoPandas implementation should look like. Since both of these take an array of geometries and return a single geometry, I suppose the API should look the same for both.

When using `polygonize`, I in 99% of cases explode the resulting GeometryCollection to individual parts. So my suggestion would be to always return a GeoSeries of an exploded geometry object coming either from `polygonize` or `build_area`.  It makes no sense to return a GeoDataFrame as we are unable to reasonably merge original attributes to the result and returning directly the output shapely returns probably isn't what user would expect.

xref #2925

cc @JamesGardiner

### Additional contract requirements

- Add a public method `GeoSeries.build_area(self, node=True)`.
- `node` is a boolean, default `True`. When `True`, the input linework is noded before the polygons are built; when `False`, noding is skipped.
- The method returns an exploded GeoSeries of Polygon geometries named `polygons`, retaining the CRS of the input.
- This change is required to expose `build_area` only; `polygonize` is not required.


- For multiple polygons returned by `build_area`, preserve the order produced by Shapely's `build_area` for the same input.
