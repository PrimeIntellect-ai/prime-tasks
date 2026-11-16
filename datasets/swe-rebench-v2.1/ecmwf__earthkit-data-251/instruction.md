to_xarray should not crash when filter_by_keys backend_kwargs is used
### What happened?

We have a GRIB file containing model level data. (Note that since param `lnsp` is only defined on level 1 this data does not form a hypercube, but it is irrelevant for this issue).

![image](https://github.com/ecmwf/earthkit-data/assets/9033020/c7beba2a-05e4-41fb-9577-98d27cee3c51)

When we use `to_xarray()` with the`filter_by_keys` option:

```python
import earthkit.data
ds = earthkit.data.from_source("file", "omega_ml.grib")
r = ds.to_xarray(
    xarray_open_dataset_kwargs={'backend_kwargs':
                               {'filter_by_keys': {'shortName': 't', 'typeOfLevel': 'hybrid', 'level': 1}}})
```

there is a crash:

```
---------------------------------------------------------------------------
AssertionError                            Traceback (most recent call last)
Cell In[8], line 1
----> 1 r = ds.to_xarray(
      2     xarray_open_dataset_kwargs={'backend_kwargs':
      3                                {'filter_by_keys': {'shortName': 't', 'typeOfLevel': 'hybrid', 'level': 1}}})

File ~/git/earthkit-data/earthkit/data/readers/grib/xarray.py:168, in XarrayMixIn.to_xarray(self, **kwargs)
    162 two_d_fields = sum(number_of_gribs(result[v]) for v in result.data_vars)
    164 # Make sure all the fields are converted
    165 # There may be more 2D xarray fields than GRB fields
    166 # if some missing dimension are filled with NaN values
--> 168 assert [HIDDEN], (
    [HIDDEN]
    173 return result

AssertionError: Not all GRIB fields were converted to xarray (9 GRIBs > 1 2D-field(s) in xarray)

```

**Note**: we could easily perform the selection in earthkit-data then convert the results to xarray. E.g. the following code would work:

```python
import earthkit.data
ds = earthkit.data.from_source("file", "omega_ml.grib")
ds.sel(param="t", typeOfLevel="hybrid", level=1).to_xarray()
```


### What are the steps to reproduce the bug?

See above.

### Version

<=0.4.0

### Platform (OS and architecture)

all

### Relevant log output

_No response_

### Accompanying data

_No response_

### Organisation

ECMWF

### Additional contract requirements

- When `to_xarray()` is called with `xarray_open_dataset_kwargs` containing `backend_kwargs.filter_by_keys`, it must not fail solely because the backend converts fewer GRIB fields than are present in the original collection. It should return the xarray dataset for the fields selected by the filter.
