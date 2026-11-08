Point normalizes latitude bizarrely
Point treats latitude periodically and thus connects the north and south
poles

~~~
>>> from geopy import Point
>>> Point(90.1, 10)
Point(-89.9, 10.0, 0.0)
~~~

This can't be considered a sensible result.  Better would be to change
latitudes outside the range [-90, 90] into nans.  Then people who
accidentally switch the order of latitude and longitude will sometimes
get a sharp poke in the eye that they've done something wrong.

### Additional contract requirements

- `geopy.point.Point(latitude, longitude, altitude=0.0)` must raise `ValueError`
  when any of the three coordinates is not finite (NaN or infinity), and when
  `latitude` is outside the inclusive range `[-90, 90]`. Longitude values
  outside `[-180, 180]` are still normalized modulo 360.
- Assigning to a `Point` item (`point[0]`, `point[1]`, `point[2]`) must raise
  `ValueError` for non-finite values and for a latitude outside `[-90, 90]`;
  longitude is normalized as in construction.
- The distance classes in `geopy.distance` (e.g. `geodesic`, `great_circle`,
  `vincenty`) must raise `ValueError` when either point has a NaN or infinite
  coordinate, or a latitude outside `[-90, 90]`.
