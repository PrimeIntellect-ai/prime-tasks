engine kwargs dictionaries are modified in place
### What happened?

`earthkit.data` modifies engine kwargs in place, causing unexpected side effects in downstream code.

### What are the steps to reproduce the bug?

```python
import earthkit.data

dataset = "reanalysis-era5-pressure-levels"
request = {
    "product_type": ["reanalysis"],
    "variable": ["geopotential"],
    "year": ["2024"],
    "month": ["03"],
    "day": ["01"],
    "time": ["13:00"],
    "pressure_level": ["1000"],
    "data_format": "grib",
}
kwargs = {"squeeze": True}
ek_ds = earthkit.data.from_source("cds", dataset, **request)
xr_ds = ek_ds.to_xarray(engine="cfgrib", xarray_open_dataset_kwargs=kwargs)
assert kwargs == {"squeeze": True}
```

### Version

v0.13.5

### Platform (OS and architecture)

Darwin MacBook-Pro-di-Bopen.local 24.3.0 Darwin Kernel Version 24.3.0: Thu Jan  2 20:24:24 PST 2025; root:xnu-11215.81.4~3/RELEASE_ARM64_T6030 arm64

### Relevant log output

```shell
AssertionError                            Traceback (most recent call last)
Cell In[3], line 17
     15 ek_ds = earthkit.data.from_source("cds", dataset, **request)
     16 xr_ds = ek_ds.to_xarray(engine="cfgrib", xarray_open_dataset_kwargs=kwargs)
---> 17 assert kwargs == {'squeeze': True}

AssertionError:
```

### Accompanying data

_No response_

### Organisation

B-Open / EQC
