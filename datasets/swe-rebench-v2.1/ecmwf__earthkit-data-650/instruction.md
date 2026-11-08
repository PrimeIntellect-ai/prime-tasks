xarray converter fails with a list of ZIP files containing a single-file ZIP
### What happened?

The code below fails, but it works if I exclude 2025 or if only 2025 is selected. I believe there's a bug that gets triggered when earthkit.data tries to open a list of ZIP files containing a single-file ZIP (i.e., a ZIP archive with only one file inside).

(I will try to add a simpler MRE later to confirm my hypothesis)

### What are the steps to reproduce the bug?

```python
import earthkit.data

collection_id = "reanalysis-oras5"
request = {
    "product_type": ["operational"],
    "vertical_resolution": "single_level",
    "variable": ["ocean_heat_content_for_the_upper_300m"],
    "year": ["2023", "2024", "2025"],
    "month": ["01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12"],
}

ds = earthkit.data.from_source("cds", collection_id, **request, split_on="year").to_xarray()
```

### Version

0.13.1

### Platform (OS and architecture)

Darwin MacBook-Pro-di-Bopen.local 24.3.0 Darwin Kernel Version 24.3.0: Thu Jan  2 20:24:24 PST 2025; root:xnu-11215.81.4~3/RELEASE_ARM64_T6030 arm64

### Relevant log output

```shell
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
Cell In[2], line 12
      3 collection_id = "reanalysis-oras5"
      4 request = {
      5     "product_type": ["operational"],
      6     "vertical_resolution": "single_level",
   (...)      9     "month": ["01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12"],
     10 }
---> 12 ds = earthkit.data.from_source("cds", collection_id, **request, split_on="year").to_xarray()

File ~/miniforge3/envs/earthkit-data/lib/python3.11/site-packages/earthkit/data/sources/multi.py:109, in MultiSource.to_xarray(self, **kwargs)
    108 def to_xarray(self, **kwargs):
--> 109     return make_merger(self.merger, self.sources).to_xarray(**kwargs)

File ~/miniforge3/envs/earthkit-data/lib/python3.11/site-packages/earthkit/data/mergers/__init__.py:109, in DefaultMerger.to_xarray(self, **kwargs)
    106 def to_xarray(self, **kwargs):
    107     from .xarray import merge
--> 109     return merge(
    110         sources=self.sources,
    111         paths=self.paths,
    112         reader_class=self.reader_class,
    113         **kwargs,
    114     )

File ~/miniforge3/envs/earthkit-data/lib/python3.11/site-packages/earthkit/data/mergers/xarray.py:75, in merge(sources, paths, reader_class, **kwargs)
     73 if paths is not None:
     74     if reader_class is not None and hasattr(reader_class, "to_xarray_multi_from_paths"):
---> 75         return reader_class.to_xarray_multi_from_paths(
     76             paths,
     77             **options,
     78         )
     80     LOG.debug(f"xr.open_mfdataset with options={options}")
     81     return xr.open_mfdataset(paths, **options)

File ~/miniforge3/envs/earthkit-data/lib/python3.11/site-packages/earthkit/data/readers/netcdf/__init__.py:73, in NetCDFReader.to_xarray_multi_from_paths(cls, paths, **kwargs)
     70 if not options:
     71     options = dict(**kwargs)
---> 73 return xr.open_mfdataset(
     74     paths,
     75     **options,
     76 )

File ~/miniforge3/envs/earthkit-data/lib/python3.11/site-packages/xarray/backends/api.py:1634, in open_mfdataset(paths, chunks, concat_dim, compat, preprocess, engine, data_vars, coords, combine, parallel, join, attrs_file, combine_attrs, **kwargs)
   1631     open_ = open_dataset
   1632     getattr_ = getattr
-> 1634 datasets = [open_(p, **open_kwargs) for p in paths1d]
   1635 closers = [getattr_(ds, "_close") for ds in datasets]
   1636 if preprocess is not None:

File ~/miniforge3/envs/earthkit-data/lib/python3.11/site-packages/xarray/backends/api.py:1634, in <listcomp>(.0)
   1631     open_ = open_dataset
   1632     getattr_ = getattr
-> 1634 datasets = [open_(p, **open_kwargs) for p in paths1d]
   1635 closers = [getattr_(ds, "_close") for ds in datasets]
   1636 if preprocess is not None:

File ~/miniforge3/envs/earthkit-data/lib/python3.11/site-packages/xarray/backends/api.py:667, in open_dataset(filename_or_obj, engine, chunks, cache, decode_cf, mask_and_scale, decode_times, decode_timedelta, use_cftime, concat_characters, decode_coords, drop_variables, inline_array, chunked_array_type, from_array_kwargs, backend_kwargs, **kwargs)
    664     kwargs.update(backend_kwargs)
    666 if engine is None:
--> 667     engine = plugins.guess_engine(filename_or_obj)
    669 if from_array_kwargs is None:
    670     from_array_kwargs = {}

File ~/miniforge3/envs/earthkit-data/lib/python3.11/site-packages/xarray/backends/plugins.py:194, in guess_engine(store_spec)
    186 else:
    187     error_msg = (
    188         "found the following matches with the input file in xarray's IO "
    189         f"backends: {compatible_engines}. But their dependencies may not be installed, see:\n"
    190         "https://docs.xarray.dev/en/stable/user-guide/io.html \n"
    191         "https://docs.xarray.dev/en/stable/getting-started-guide/installing.html"
    192     )
--> 194 raise ValueError(error_msg)

ValueError: did not find a match in any of xarray's currently installed IO backends ['netcdf4', 'scipy', 'cfgrib', 'earthkit']. Consider explicitly selecting one of the installed engines via the ``engine`` parameter, or installing additional IO dependencies, see:
https://docs.xarray.dev/en/stable/getting-started-guide/installing.html
https://docs.xarray.dev/en/stable/user-guide/io.html
```

### Accompanying data

_No response_

### Organisation

B-Open / EQC

### Additional contract requirements

- Converting a list of ZIP archives, where each archive contains a single file, to xarray must succeed.
