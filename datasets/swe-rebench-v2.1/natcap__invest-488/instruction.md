Offer a more helpful validation message when a user provides an OVR file
This has happened on the forums a couple of times now, but here's the latest example: https://community.naturalcapitalproject.org/t/pollination-model-error-after-updating-to-invest-3-8-0-unable-to-initiate-run/856

When a user provides an overviews file instead of the GeoTiff it's associated with, the overviews file triggers the validation error stating that the file must be projected.  It would be nice if we could check if this file is an overviews file and provide a more specific and helpful error message for this common use case.

Marked as a 3 difficulty because the slightly more interesting thing will be figuring out how to build an overviews file within GDAL as part of the tests.  I think maybe @richpsharp has done that before?

### Additional contract requirements

- When a `.tif.ovr` file is supplied for raster validation, the returned error message must contain the exact text `File found to be an overview`.
