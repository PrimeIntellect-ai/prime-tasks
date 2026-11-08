Trying to create a raster from an empty vector's extents crashes with cryptic error
This came up [on the forums recently](https://community.naturalcapitalproject.org/t/hra-model-typeerror-nonetype-object-is-not-subscriptable/1607/3?u=jdouglass), where a user was trying to create a raster from vector extents when the vector had no features whatsoever.

Minimally reproducible example:

```python
import pygeoprocessing

from osgeo import gdal, ogr, osr

SRS = osr.SpatialReference()
SRS.ImportFromEPSG(4326)

# Make a vector with no features.
SHP_DRIVER = ogr.GetDriverByName('ESRI Shapefile')
VECTOR_PATH = 'testtest.shp'
VECTOR = SHP_DRIVER.CreateDataSource(VECTOR_PATH)
LAYER = VECTOR.CreateLayer('testtest', SRS)
LAYER = None
VECTOR = None

pygeoprocessing.create_raster_from_vector_extents(
    VECTOR_PATH, 'out_raster.tif', (20, -20), gdal.GDT_Byte, 255)
```

Which results in

```python
Traceback (most recent call last):
  File "test.py", line 16, in <module>
    VECTOR_PATH, 'out_raster.tif', (20, -20), gdal.GDT_Byte, 255)
  File "/Users/jdouglass/Downloads/HRA_lab1/env37-conda/lib/python3.7/site-packages/pygeoprocessing/geoprocessing.py", line 1004, in create_raster_from_vector_extents
    abs((shp_extent[1] - shp_extent[0]) / target_pixel_size[0])))
TypeError: 'NoneType' object is not subscriptable
```

This appears to still be an issue for determining both [n_rows](https://github.com/natcap/pygeoprocessing/blob/main/src/pygeoprocessing/geoprocessing.py#L1009) and [n_cols](https://github.com/natcap/pygeoprocessing/blob/main/src/pygeoprocessing/geoprocessing.py#L1013) and is present in `main`.

This is obviously a case of a broken contract, but it would still be nice to raise a human-readable error message.
