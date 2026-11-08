irradiance.erbs behavior near zenith = 90
`irradiance.erbs` has a few issues when zenith approaches 90:

* kt blows up. This can be addressed using `irradiance.clearness_index` and a `min_cos_zenith` kwarg.
* dni blows up. This can be addressed with a `max_zenith` kwarg.

Similar to `disc` issues addressed in #540 and #400.

**Versions:**
 - ``pvlib.__version__``: 0.6.1
