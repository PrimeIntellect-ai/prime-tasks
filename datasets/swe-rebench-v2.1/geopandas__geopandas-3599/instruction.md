ENH: from_features - allow not passing in "properties"
https://github.com/geopandas/geopandas/blob/5c8ae832e030228b5deec02588c4e1b78dee0f18/geopandas/geodataframe.py#L651

It checks if `properties` is None. Any issues [HIDDEN] so this scenario could be supported:
```python
collection = {
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "id": "095af6d6-bfcd-4cca-a72c-bf2efd1cf917",
            "geometry": {
                "type": "Point",
                "coordinates": [-10.0, -10.0]
            }
        },
        {
            "type": "Feature",
            "id": "a7ad51b6-ad2d-4f75-806a-d68ab9e07e5b",
            "geometry": {
                "type": "Point",
                "coordinates": [-10.1, -10.1]
            }
        }
    ]
}
gdf = geopandas.GeoDataFrame.from_features(collection["features"])
```

### Additional contract requirements

- `GeoDataFrame.from_features` must accept a FeatureCollection or iterable of features whose features omit `properties`, produce rows containing their supplied geometries, and not add a synthetic `properties` column.
