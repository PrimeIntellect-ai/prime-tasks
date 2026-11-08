`ValueError: too many values to unpack` when inspecting GeoBox
I have a raster in Bathymetry Attributed Grid (bag) format ([supported by GDAL](https://gdal.org/drivers/raster/bag.html)).

I'm attempting to load it with `rioxarray`, then analyse and reproject it with `odc-geo` tools. However, when I attempt to inspect its GeoBox via `.odc.geobox`, I get a `ValueError: too many values to unpack (expected 2)` error:
```
import rioxarray
import odc.geo.xr

path = 'https://dotazprdauegisextpubst01.blob.core.windows.net/transport-wa-public/bathymetry/rasters/PS20190310_Laser.bag'
ds = rioxarray.open_rasterio(path, masked=True).to_dataset(dim="band")
ds.odc.geobox
```

Is this a problem with going from `rioxarray` > `odc.geo`, or something about the data's CRS or data format itself?


Full error:
```
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
File /env/lib/python3.10/site-packages/IPython/core/formatters.py:344, in BaseFormatter.__call__(self, obj)
    342     method = get_real_method(obj, self.print_method)
    343     if method is not None:
--> 344         return method()
    345     return None
    346 else:

File /env/lib/python3.10/site-packages/odc/geo/geobox.py:286, in GeoBoxBase._repr_html_(self)
    284 def _repr_html_(self):
    285     # pylint: disable=protected-access
--> 286     return self._ui._repr_html_()

File /env/lib/python3.10/site-packages/odc/geo/ui.py:338, in PixelGridDisplay._repr_html_(self)
    336     authority = crs.authority
    337     wkt = crs.to_wkt(pretty=True).replace("\n", "<br/>").replace(" ", "&nbsp;")
--> 338     units = crs.units[0]
    339     svg_global_txt = svg_base_map(
    340         sz=200, target=self._src.geographic_extent.centroid.coords[0]
    341     )
    343 if authority == ("", ""):

File /env/lib/python3.10/site-packages/odc/geo/crs.py:216, in CRS.units(self)
    213     return "degrees_north", "degrees_east"
    215 if self.projected:
--> 216     [HIDDEN]
    217     return x.unit_name, y.unit_name
    219 raise ValueError("Neither projected nor geographic")

ValueError: too many values to unpack (expected 2)
```
GDAL info:
```
Driver: BAG/Bathymetry Attributed Grid
Files: none associated
Size is 1920, 1600
Coordinate System is:
COMPOUNDCRS["GDA94 / MGA zone 50 + Instantaneous Water Level Height",
    PROJCRS["GDA94 / MGA zone 50",
        BASEGEOGCRS["GDA94",
            DATUM["Geocentric Datum of Australia 1994",
                ELLIPSOID["GRS 1980",6378137,298.257222101,
                    LENGTHUNIT["metre",1]]],
            PRIMEM["Greenwich",0,
                ANGLEUNIT["degree",0.0174532925199433]],
            ID["EPSG",4283]],
        CONVERSION["UTM zone 50S",
            METHOD["Transverse Mercator",
                ID["EPSG",9807]],
            PARAMETER["Latitude of natural origin",0,
                ANGLEUNIT["degree",0.0174532925199433],
                ID["EPSG",8801]],
            PARAMETER["Longitude of natural origin",117,
                ANGLEUNIT["degree",0.0174532925199433],
                ID["EPSG",8802]],
            PARAMETER["Scale factor at natural origin",0.9996,
                SCALEUNIT["unity",1],
                ID["EPSG",8805]],
            PARAMETER["False easting",500000,
                LENGTHUNIT["metre",1],
                ID["EPSG",8806]],
            PARAMETER["False northing",10000000,
                LENGTHUNIT["metre",1],
                ID["EPSG",8807]]],
        CS[Cartesian,2],
            AXIS["easting",east,
                ORDER[1],
                LENGTHUNIT["metre",1]],
            AXIS["northing",north,
                ORDER[2],
                LENGTHUNIT["metre",1]],
        ID["EPSG",28350]],
    VERTCRS["Instantaneous Water Level Height",
        VDATUM["Instantaneous Water Level"],
        CS[vertical,1],
            AXIS["up",up,
                LENGTHUNIT["metre",1]],
        ID["EPSG",5829]]]
Data axis to CRS axis mapping: 1,2,3
Origin = (518748.000000000000000,7718414.000000000000000)
Pixel Size = (1.000000000000000,-1.000000000000000)
Metadata:
  AREA_OR_POINT=Point
  BagVersion=1.6.2
  BAG_DATETIME=2019-03-27T05:06:54Z
Corner Coordinates:
Upper Left  (  518748.000, 7718414.000) (117d10'47.84"E, 20d38' 0.23"S)
Lower Left  (  518748.000, 7716814.000) (117d10'47.91"E, 20d38'52.28"S)
Upper Right (  520668.000, 7718414.000) (117d11'54.19"E, 20d38' 0.16"S)
Lower Right (  520668.000, 7716814.000) (117d11'54.26"E, 20d38'52.21"S)
Center      (  519708.000, 7717614.000) (117d11'21.05"E, 20d38'26.22"S)
Band 1 Block=1920x1 Type=Float32, ColorInterp=Undefined
  Description = elevation
  Min=-1.758 Max=21.531
  NoData Value=1e+06
Band 2 Block=1920x1 Type=Float32, ColorInterp=Undefined
  Description = uncertainty
  Min=0.000 Max=23.503
  NoData Value=1e+06
```

### Additional contract requirements

- `CRS.units` must return the horizontal units of a projected compound CRS even when it also has a vertical axis. Return the units as a `(y-axis, x-axis)` tuple; for the CRS shown above, both values are `"metre"`.
- Inspecting the reported raster's GeoBox via `.odc.geobox` must not raise the reported `ValueError` because its CRS has an additional vertical axis.
