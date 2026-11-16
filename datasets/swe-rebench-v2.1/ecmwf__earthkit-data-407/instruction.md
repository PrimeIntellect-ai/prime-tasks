Add option to subset field values in to_numpy() method
### Is your feature request related to a problem? Please describe.

If we have a fieldlist `to_numpy()` gives back a 2D numpy array containing all the field values per field. We can slice this array according to the second (per field axis) like that:

```python
ds = from_source("file", "my.grib")
v = ds.to_numpy(flatten=True)[:, :4]
```

This could be done in a more memory efficient way if we [HIDDEN] and `to_numpy()` returned the already sliced 2D array.  This could be done e.g. by implementing the following interface:

```python
ds = from_source("file", "my.grib")
v = ds.to_numpy(flatten=True, index=slice(None, 4))
```

### Describe the solution you'd like

_No response_

### Describe alternatives you've considered

_No response_

### Additional context

_No response_

### Organisation

ECMWF

### Additional contract requirements

When `index` is supplied to a field-list `to_numpy()` call, selection is performed per field so that the full unselected combined field-list array does not need to be materialized before the selected values are returned. The result retains one output row per field.
