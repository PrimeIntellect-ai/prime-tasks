Implement `__geo_interface__`
[`__geo_interface__`](https://gist.github.com/sgillies/2217756) is a way for Python objects to return geojson (-like) representations of themselves. Should pystac objects implement this?

This might be helpful for cases like https://github.com/stac-utils/pystac-client/issues/146, where libraries want to support a range of geojson-like objects without having to know how to convert each particular object to geojson.

### Additional contract requirements

A PySTAC `Item` should expose `__geo_interface__` as an attribute for geospatial consumers. Its geojson-like value should represent the item's geometry, either as a geometry mapping or as a Feature containing that geometry.
