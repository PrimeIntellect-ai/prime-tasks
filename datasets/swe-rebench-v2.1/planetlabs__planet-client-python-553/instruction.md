implement data api support for creating a data search filter
similar to `order_request` ([ref](https://github.com/planetlabs/planet-client-python/blob/main/planet/order_request.py)), implement `data_filter`, which supports creation of a data search filter. This is the backend for `planet data filter` CLI command

### Additional contract requirements

The `planet.data_filter` module provides builders for filters that can be submitted to the Data API:

- `and_filter` and `or_filter` accept nested filters and produce the corresponding composite filter; `not_filter` wraps one nested filter as a negation.
- `range_filter` accepts a field name and optional `gt`, `lt`, `gte`, and `lte` numeric bounds. At least one bound is required; otherwise it raises `exceptions.PlanetError`.
- `date_range_filter` accepts the same bounds as datetimes and represents each supplied bound as an RFC 3339 timestamp. Equivalent timestamp representations, including different offsets for the same instant, are valid. At least one bound is required; otherwise it raises `exceptions.PlanetError`.
- `update_filter` accepts a field name and update-time bounds `gt` and/or `gte`, represented as RFC 3339 timestamps. At least one of those bounds is required; otherwise it raises `exceptions.PlanetError`.
- `geometry_filter` represents a geometry criterion for the item geometry.
- `number_in_filter` and `string_in_filter` accept a field name and values to match against that field.
- `asset_filter` represents criteria based on asset types, and `permission_filter` represents the permission to download assets.

Each builder returns the appropriate Data API filter object, with its filter kind, field name where applicable, and criteria. Filter order is immaterial for AND/OR composition and asset lists; duplicate entries do not change membership semantics.
