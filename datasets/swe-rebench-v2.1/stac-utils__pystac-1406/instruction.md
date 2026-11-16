Calling `bands` property on a `pystac.extensions.eo.EOExtension` can result in RecursionError
The following code snippet leads to a `RecursionError` on pystac 1.10.1:
```python
collection = pystac.read_file('https://planetarycomputer.microsoft.com/api/stac/v1/collections/landsat-c2-l2')
item_assets = collection.ext.item_assets
item_asset = list(item_assets.values())[2]
item_asset.ext.eo.bands
```

When inspecting the STAC collection, it can be seen that the ´bands´ in the `eo` extension of `item_asset` doesn't have the required `name` field. Instead of a `RequiredPropertyMissing`, however, we get a `RecursionError`, seemingly because of the following:

The error message of `RequiredPropertyMissing` reads
```python
[HIDDEN]
```
`Band.__repr__` is defined as
```python
[HIDDEN]
```
[HIDDEN]

### Additional contract requirements

- If an EO band is missing its required `name`, accessing that name must raise `RequiredPropertyMissing`, not `RecursionError`.
