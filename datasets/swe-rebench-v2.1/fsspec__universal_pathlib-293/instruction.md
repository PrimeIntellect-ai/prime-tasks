expanduser implementation for geopandas
GeoPandas `read_file` and `to_file` attempts a [`path.expanduser()` ](https://github.com/geopandas/geopandas/blob/a78dbf3a48eaa0f84d12d9935fce4927e381d146/geopandas/io/file.py#L177-L178) which raises `NotImplementedError` when `path` is a `UPath`.

Is it intended that `UPath.expanduser` must raise `NotImplementedError`, or is it a matter of not getting round to it yet? For context I have had this issue when attempting to read/write on GCS.

In the meantime I am using a workaround to read/write via a `io.BytesIO` buffer, e.g.:
```python
# write
with io.BytesIO() as buffer:
  gdf.to_file(buffer, driver="GeoJSON")
  buffer.seek(0)
  path.write_bytes(buffer.read())

# read
with io.BytesIO(path.read_bytes()) as buffer:
  gdf = gpd.read_file(buffer)
```

### Additional contract requirements

- `UPath.expanduser()` must expand a leading `~` to the current user's home directory and return the resulting `UPath`.
