Add geographical coordinate access to FieldList
On a GribField we can extract the latitudes/longitudes with [to_latlon](https://earthkit-data.readthedocs.io/en/latest/_api/data/readers/grib/codes/index.html). It returns a dict as:

`{"lat": array, "lon": array}`

This method is not available on a FieldList. The proposal is that on a FieldList `to_latlon` could return the `to_latlon` value from the first field if the grid geometry is the same for all the fields. Otherwise it would throw an exception.

The situation is exactly the same for [to_points](https://earthkit-data.readthedocs.io/en/latest/_api/data/readers/grib/codes/index.html), so it should be implemented in a similar way on a FieldList.

Relates to #116
