rasterio DatasetReader complex_int16 incompatible with auto chunking of dask (rioxarray.open_rasterio)
#### Code Sample, a copy-pastable example if possible

```python
import numpy as np
import rasterio
import rioxarray

filename = "complex_int16.tiff"

with rasterio.open(filename, mode='w', width=16, height=16, count=1, dtype="complex_int16") as writer:
    writer.write(np.array([[[ i*j for j in range(16)] for i in range(16)]]))

rioxarray.open_rasterio(filename, chunks=True)
```

#### Problem description

When opening a file with `rioxarray.open_rasterio` passing `chunks=True`, `rasterio.DatasetReader` can have `"complex_int16"` dtype, that is incompatible with `dask.core.normalize_chunk` dtype parameter (line 682 in `rioxarray._io`) and cause `TypeError: data type 'complex_int16' not understood`.

[HIDDEN]

#### Expected Output

`rioxarray.open_rasterio` should work and provide a `xarray.DataArray` with `np.complex64` dtype in the case of processing a rasterio file with `complex_int16` dtype.

#### Environment Information

- Tested with rioxarray >= 0.10.2
- rasterio ==1.2.10
- Python 3.9.9
- Linux-5.13.0-51-generic-x86_64-with-glibc2.31

#### Installation method
 - `pip install rioxarray==${TARGET_VERSION}`
