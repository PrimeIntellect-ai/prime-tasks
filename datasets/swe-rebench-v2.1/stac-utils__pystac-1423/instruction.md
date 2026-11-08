Order of Item fields
Hi all!
When generating Items using `item.save_object( )`, I expected the order of fields in my JSON files to reflect the order as listed [here](https://github.com/radiantearth/stac-spec/blob/master/item-spec/item-spec.md#item-fields) and the [example file](https://github.com/radiantearth/stac-spec/blob/master/examples/simple-item.json). However, this is not the case (see below) and I was wondering if I'm just missing something or if this is not yet supported by pySTAC?
In terms of machine-readability it doesn't matter of course, but I'm working on a data product where the metadata output should be consistent and logical (including order of main fields).

Expected order:
```
{
    "type": "Feature",
    "stac_version": "1.0.0",
    "stac_extensions": [...],
    "id": "...",
    "geometry": {...},
    "bbox": [...],
    "properties": {...},
    "links": [...],
    "assets": {...}
}
```
Actual order:
```
{
    "type": "Feature",
    "stac_version": "1.0.0",
    "id": "...",
    "properties": {...},
    "geometry": {...},
    "links": [...],
    "assets": {...},
    "bbox": [...],
    "stac_extensions": [...]
}
```
