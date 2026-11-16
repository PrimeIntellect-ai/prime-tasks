Opening VRT with GCPs results in DataArray of zeros
#### Code Sample, a copy-pastable example if possible

The following loads geo coordinates correctly, but the data array is all zeros
```python
import rioxarray
import rasterio
from rasterio.vrt import WarpedVRT

with rasterio.open('cint16.tif') as src:
    with WarpedVRT(src) as vrt:
        rds = rioxarray.open_rasterio(vrt)

rds.values.any() # False
```
#### Problem description

Opening a WarpedVRT with ground control points results in an array of zeros. But using `rio.reproject` works as expected:

#### Expected Output

There should be non-zero data values in the DataArray

```
da = rioxarray.open_rasterio('cint16.tif')
da = da.astype('f4')
daG = da.rio.reproject('EPSG:4326')
daG.values.any() # True
```

I used `cint16.tif` because it is already in rioxarray test data, but here is a gist with another data product with uint16 dtype with some plots too
https://gist.github.com/scottyhq/211d417aa826593d8b3cac1f3367be68


#### Environment Information

```
rioxarray (0.10.3) deps:
  rasterio: 1.3a3
    xarray: 2022.3.0
      GDAL: 3.4.1

Other python deps:
     scipy: 1.8.0
    pyproj: 3.3.0

System:
    python: 3.9.12 | packaged by conda-forge | (main, Mar 24 2022, 23:25:59)  [GCC 10.3.0]
executable: /srv/conda/envs/sarsen/bin/python
   machine: Linux-5.4.172-90.336.amzn2.x86_64-x86_64-with-glibc2.27
```

#### Installation method
 - conda / conda-forge
