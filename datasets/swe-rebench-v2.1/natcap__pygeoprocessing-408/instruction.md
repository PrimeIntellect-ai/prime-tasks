`raster_map` errors on valid combinations of dtype and nodata value
If `target_dtype` and `target_nodata` are provided to `raster_map`, it tries to confirm that the nodata value fits into the dtype using `numpy.can_cast`. This does not work as I expected:
```
>>> float32_min = float(numpy.finfo(numpy.float32).min)
>>> numpy.can_cast(float32_min, numpy.float32)
False
```
It's usually not necessary to set the `target_dtype` and `target_nodata`, but this bug prevents us from doing so in some cases.
