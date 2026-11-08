Add bases module
Add bases module which provides `DataArrayClass`, a base class for dataclasses.

```python
from xarray_dataclasses import DataArray, DataArrayClass


class Image(DataArrayClass):
    data: DataArray[("x", "y"), float]
    x: DataArray["x", int] = 0
    y: DataArray["y", int] = 0
```

### Additional contract requirements

`DataArrayClass` must be importable from `xarray_dataclasses.bases` as well as from the package root shown above. A subclass written like `Image` in the example, without its own `@dataclass` decorator, must have its declared `data`, `x`, and `y` annotations represented as dataclass fields.
