usage of __geo_interface__?
Hi there,
I am trying to use the \_\_geo\_interface\_\_ concept for defining a search geometry.
From how interpret [Sean Gillies' Post](https://gist.github.com/sgillies/2217756), I can define it as a regular GeoJSON:
```python
geometry = {'type': 'Feature',
            'geometry': {'type': 'Polygon',
                         'coordinates': [[[10.0, 50.0], [10.0, 55.0],
                                          [15.0, 55.0], [15.0, 50.0], [10.0, 50.0]]]
                         }
            }
```
...which can then for example be read into geopandas:
```python
df = GeoDataFrame.from_features(features=geometry)
```
However, when I pass this geometry definition to `Client.search`:
```python
catalog = Client.open(url='https://planetarycomputer.microsoft.com/api/stac/v1')
result = catalog.search(collections='sentinel-1-grd',
                        max_items=None,
                        intersects=geometry,
                        datetime=['2022-01-01', '2022-01-02'])
```
...I get this error:
```python
...
body -> intersects -> type
  unexpected value; permitted: 'Polygon' (type=value_error.const; given=Feature; permitted=['Polygon'])
...
```

So, I need to define my geometry like this to get a working example:
```python
geometry = {'type': 'Polygon',
            'coordinates': [[[10.0, 50.0], [10.0, 55.0],
                             [15.0, 55.0], [15.0, 50.0],
                             [10.0, 50.0]]]}
```

Is this expected behavior? Is the latter a correct geometry as intended for \_\_geo\_interface\_\_?

### Additional contract requirements

- When `intersects` is provided as a GeoJSON Feature dictionary, accept it and use its `geometry` value as the search intersection, equivalent to supplying that geometry directly.
