0.3.3 does not support/has trouble with stac api version < 1.0.0
Have got latest version of the `pystac-client==0.3.3` but having trouble to read from older stac API versions

The issue is when trying to use the `pystac-client==0.3.3`. with https://earth-search.aws.element84.com/v0/ endpoint

Or has the `search` syntax changed from the 0.3.2 versions?

Thanks for any help/comment.

Peter

### Additional contract requirements

- A client opened against an older STAC API, including the `/v0/` endpoint in the report, must be able to execute a search through `Client.search` when the API's `search` link advertises the generic JSON media type (`MediaType.JSON`) rather than GeoJSON. By default, this link must be accepted and the search must return an iterable result for the supplied search parameters; using an older API must not require different search syntax.
