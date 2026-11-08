CV does not handle `nan` in bathymetry
A raster with `nan` as `nodata` will yield `nan` values from `extract_bathymetry_along_ray` if any of the fetch ray overlaps nodata.

This looks like a case where we're using [HIDDEN] [HIDDEN].

### Additional contract requirements

- When bathymetry raster nodata is NaN, extracting values along a fetch ray must treat those samples as nodata so their presence does not contaminate the extracted depths.
