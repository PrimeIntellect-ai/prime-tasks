Add typing module
Add typing module which provides a type for `xarray.DataArray` with fixed `dims` and `dtype`.

```python
DataArray[("x", "y"), "f8"]

# DataArray[('x', 'y'), float64]
```

The type can be instantiated.

```python
DataArray[("x", "y"), "f8"]([[0, 1], [2, 3]])

# <xarray.DataArray (x: 2, y: 2)>
# array([[0., 1.],
#        [2., 3.]])
# Dimensions without coordinates: x, y
```

### Additional contract requirements

- The type is the public class `DataArray` in the module `xarray_dataclasses.typing`.
- Subscripting with a two-element tuple, `DataArray[dims, dtype]`, returns a new subclass of `DataArray`. The returned class records the requested dimensions in its `dims` attribute (a single string is treated as a one-element sequence) and the requested dtype in its `dtype` attribute (converted to a NumPy dtype). A value of `None` means that the corresponding constraint is not fixed.
- The unparameterized `DataArray` class has `dims` and `dtype` both equal to `None`.
- The name of the returned subclass encodes its parameters: for `DataArray[('x', 'y'), 'f8']` the name is `DataArray[('x', 'y'), float64]`.
- `isinstance(inst, DataArray[dims, dtype])` returns `True` if and only if `inst` is an `xarray.DataArray` whose dimensions and dtype match every non-`None` constraint; otherwise it returns `False`.
