read_csv function should have an option to set the crs
At the moment it is not possible to define a crs while reading trackintel data directly from .csv. I think this would be a nice enhancement.

Example code:
```python
tpls_file = os.path.join('tests', 'data', 'geolife', 'geolife_triplegs_short.csv')
tpls = ti.read_triplegs_csv(tpls_file, tz='utc', index_col='id')
print(tpls.crs)
```

### Additional contract requirements

- `read_positionfixes_csv`, `read_triplegs_csv`, `read_staypoints_csv`, and `read_locations_csv` should accept an optional `crs` argument. When supplied, the returned GeoDataFrame must have that CRS assigned. When omitted, the existing no-CRS behavior should be preserved.
