implement STAC API Query fragment
For STAC providers, STAC API Item Search has limited filtering capabilities (`collections`, `ids`, `bbox` / `intersects`, `datetime`).

However, it does not contain a formalized way to filter based on arbitrary fields in an Item. For example, there is no way to express the filter *"`item.properties.eo:cloud_cover` is less than 10"*

This can be improved using properties filtering provided by the [STAC API - Query Fragment](https://github.com/radiantearth/stac-api-spec/blob/master/fragments/query/README.md)

*Note that it is planned to be deprecated in favor of [STAC API - Filter Fragment](https://github.com/radiantearth/stac-api-spec/blob/master/fragments/filter/README.md), providing CQL filtering. But for the moment, available STAC API provider do not support  it.*

### Additional contract requirements

- For STAC providers, a search parameter naming an arbitrary Item field must be
  translated into a STAC API Query fragment in the generated search request. The
  generated request body must contain a `query` object mapping the field name to an
  operator object using the `eq` operator and the value rendered as a string. For
  example, the search parameter `eo:cloud_cover=10` must produce
  `{"query": {"eo:cloud_cover": {"eq": "10"}}}`. This applies both to STAC
  extension field names containing a colon (e.g. `eo:cloud_cover`) and to plain
  field names.

- For the motivating cloud-cover comparison, use the STAC provider search
  parameter `cloudCover` with a numeric limit (for example, `cloudCover=10`).
  The generated Query fragment must map `eo:cloud_cover` to an `lte` operator
  with that numeric limit.
