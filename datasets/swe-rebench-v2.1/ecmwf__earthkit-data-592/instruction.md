`to_xarray` from GRIB dropping units
### What happened?

When calling `to_xarray()` on `GRIBReader` objects in earthkit-data, somnetimes the data units are lost. This seems to happen when there is a single variable in the GRIB input - but when there are multiple variables, the units are correctly carried into the xarray object.

### What are the steps to reproduce the bug?

```python
import earthkit.data

data = earthkit.data.from_source(
    'cds',
    'reanalysis-era5-single-levels',
    {
        'product_type': 'reanalysis',
        'variable': '2m_temperature',
        'year': '2024',
        'month': '08',
        'day': '09',
        'time': '18:00',
    },
)

ds = data.to_xarray()
```

If you look at the global and variable attributes of `ds`, there are no units in either. However, if we slightly tweak the above request to as for two variables as below, then the two variables in `ds` both have their correct units in the variable attributes.

```python
import earthkit.data

data = earthkit.data.from_source(
    'cds',
    'reanalysis-era5-single-levels',
    {
        'product_type': 'reanalysis',
        'variable': ['2m_temperature', 'total_precipitation'],
        'year': '2024',
        'month': '08',
        'day': '09',
        'time': '18:00',
    },
)

ds = data.to_xarray()
```

### Version

0.11.4

### Platform (OS and architecture)

MacOS

### Relevant log output

_No response_

### Accompanying data

_No response_

### Organisation

ECMWF

### Additional contract requirements

- For a single-field GRIB conversion producing variable `t`, the dataset global attributes must not include `standard_name` or `long_name`. The attributes of `ds["t"]` must include `standard_name: "air_temperature"`, `long_name: "Temperature"`, and `units: "K"`.
- For this conversion, `ds.attrs` must include `param: "t"`, `paramId: 130`, `class: "od"`, `stream: "oper"`, and `institution: "ECMWF"`.
