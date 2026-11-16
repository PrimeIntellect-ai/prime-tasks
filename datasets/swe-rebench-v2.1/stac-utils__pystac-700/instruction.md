pystac.extensions.file.MappingObject doesn't work
`pystac.extensions.file.MappingObject` is broken and/or the docs should not specify to use it. An example:

```python
from pystac.extensions.file import FileExtension, MappingObject

FILE_SIZE = 100
VALUES = {
    1: "Temperate or sub-polar needleleaf forest",
    2: "Sub-polar taiga needleleaf forest",
    3: "Tropical or sub-tropical broadleaf evergreen forest",
...
}

values: List[MappingObject] = [
    MappingObject.create(values=[i], summary=s) for i, s in VALUES.items()
]

file_ext = FileExtension.ext(data_asset, add_if_missing=True)
file_ext.apply(size=FILE_SIZE, values=values)
```
results in
```
TypeError: Object of type MappingObject is not JSON serializable
```
when saving the STAC. The following change is a viable workaround:
```python
values: List[Any] = [
    dict(values=[i], summary=s) for i, s in VALUES.items()
]
```

### Additional contract requirements

- `pystac.extensions.file.MappingObject` must provide a class method
  `from_dict(d: Dict[str, Any]) -> MappingObject` that creates an instance whose
  `values` and `summary` are populated from the supplied dictionary.
- `pystac.extensions.file.MappingObject` must provide an instance method
  `to_dict() -> Dict[str, Any]` that returns the mapping object's properties as a
  plain dictionary suitable for JSON serialization and for storage in STAC asset
  extra fields.
- Applying `MappingObject` values through the file extension must store them in the
  asset's `file:values` extra field as plain dictionaries (for example
  `{"values": [...], "summary": "..."}`), so that the resulting STAC data is JSON
  serializable.
