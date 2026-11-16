Crash when trying to parse netcdf file for fields
### What happened?

When we get the following data from cds:

```python
import earthkit.data
lc_data = earthkit.data.from_source(
    "cds",
    'satellite-land-cover',
   {
     'year': '2022',
     'version': 'v2.1.1',
     'variable': 'all',
     'format': 'zip',
   }
)
```
earthkit-data crashes during parsing the fields in the NetCDF file the zip file contains.

```
File ~/git/earthkit-data/earthkit/data/readers/netcdf.py:169, in get_fields_from_ds(ds, array_backend, field_type, check_only)
    167     v = ds[name]
    168     skip.update(getattr(v, "coordinates", "").split(" "))
--> 169     skip.update(getattr(v, "bounds", "").split(" "))
    170     skip.update(getattr(v, "grid_mapping", "").split(" "))
    172 for name in ds.data_vars:

File /opt/homebrew/Caskroom/miniforge/base/envs/dev_ecc/lib/python3.10/site-packages/xarray/core/common.py:278, in AttrAccessMixin.__getattr__(self, name)
    276         with suppress(KeyError):
    277             return source[name]
--> 278 raise AttributeError(
    279     f"{type(self).__name__!r} object has no attribute {name!r}"
    280 )

AttributeError: 'DataArray' object has no attribute 'split'
```

### What are the steps to reproduce the bug?

See above.

### Version

<-0.5.5

### Platform (OS and architecture)

all

### Relevant log output

_No response_

### Accompanying data

_No response_

### Organisation

ECMWF
