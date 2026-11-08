getElevationsAlongPath
It appears this library is missing the getElevationsAlongPath functionality for elevations.

Below is an example of the request:

https://maps.googleapis.com/maps/api/elevation/json?path=36.578581,-118.291994|36.23998,-116.83171&samples=3&key=[YOUR API KEY]

Instead of 'locations' as the parameter, both 'path' and 'samples' parameters are provided instead.

### Additional contract requirements

- The `path` parameter is serialized in the request query as the pipe-separated (`|`) list of `lat,lng` pairs, e.g. `path=36.578581,-118.291994|36.23998,-116.83171`.
- The `samples` parameter is sent as-is in the request query.
- A failure of the underlying HTTP request (for example, a non-2xx response) rejects the returned Promise.
