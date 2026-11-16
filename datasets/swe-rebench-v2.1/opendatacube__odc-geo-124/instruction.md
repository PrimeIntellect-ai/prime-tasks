Output resolution arguments are dropped in `[Dataset].odc.reproject(...)`
I have a 1 metre LiDAR dataset that I am loading from a raster file via `rioxarray`. I would like to reproject this dataset into a specific CRS (Australian Albers) and resolution (10 metres), similar to using `output_crs` and `resolution` in `datacube.load()`.

I can easily reproject to the CRS like this:
```
ds.odc.reproject(how="EPSG:3577")
```
However, specifying `resolution` has no effect:
```
ds.odc.reproject(how="EPSG:3577", resolution=10)
```

Although one workaround would be to manually create a new GeoBox with my custom CRS and resolution, I would love to be able to simply set both CRS and resolution directly within `.odc.reproject()` for ease of use - especially since in this example I don't even need a particularly precise output grid (e.g. snapping/alignment), just a quick and dirty transformation to a specific CRS and lower resolution so I can more easily process a very large LIDAR dataset).

Full code example:
```
import rioxarray
import odc.geo.xr

ds = rioxarray.open_rasterio(
    filename="https://dotazprdauegisextpubst01.blob.core.windows.net/transport-wa-public/bathymetry/rasters/HD20180814_Laser.bag",
    band_as_variable=True,
    chunks={},
)

ds_albers = ds.odc.reproject(how="EPSG:3577")
ds_albers_10m = ds.odc.reproject(how="EPSG:3577", resolution=10)

print(ds_albers.odc.geobox.resolution)
print(ds_albers_10m.odc.geobox.resolution)
```
