Collection `full_copy` and `clone` don't actually deepcopy
When I `clone` or `full_copy` a Collection, its extra_fields, are not deepcopied. Mutating the copy will mutate the original:

```python
from pystac import Collection, Extent, SpatialExtent, TemporalExtent

data = {"test": "1"}
a = Collection(id="test", description="test", extra_fields=data, extent=Extent(spatial=SpatialExtent(bboxes=[0,0,0,0]), temporal=TemporalExtent(intervals=[0,0])))

b = a.full_copy()
b.extra_fields.pop("test")
a.extra_fields  # {}
```

This probably also happens to Catalogs and to more fields than just `extra_fields` as well.

### Additional contract requirements

Cloning or full-copying a Collection must leave its mutable state independent of the source. Mutating the copy must not affect the source's `extra_fields` (including nested mutable values), extent, keywords, providers, summaries, or `stac_extensions`.
