Cryptic error when invalid interpolation option passed to warp_raster()
While redeveloping InVEST's Coastal Blue Carbon, I came across the following cryptic exception:

```python
    def wrapper_GDALWarpDestName(*args):
        """wrapper_GDALWarpDestName(char const * dest, int object_list_count, GDALWarpAppOptions warpAppOptions, GDALProgressFunc callback=0, void * callback_data=None) -> Dataset"""
>       return _gdal.wrapper_GDALWarpDestName(*args)
E       TypeError: in method 'wrapper_GDALWarpDestName', argument 4 of type 'GDALWarpAppOptions *'
```

After some debugging, this came down to an interpolation option of `'nearest'` being passed to `pygeoprocessing.warp_raster` via `align_and_resize_raster_stack` instead of `'near'`.

This is obviously programmer error, but it took a surprisingly long time to get to the bottom of this and it would be really nice to have a more informative exception if invalid warp options are being passed to GDAL.
