server mode queryables
Add queryables, available through `/queryables` and `/collections/<PRODUCT_TYPE>/queryables`.

See https://github.com/radiantearth/stac-api-spec/blob/master/fragments/filter/README.md#queryables for documentation and https://planetarycomputer.microsoft.com/api/stac/v1/collections/sentinel-2-l2a/queryables for an example.

- `/queryables` should be minimal
- `/collections/<PRODUCT_TYPE>/queryables` should be build using product type queryable parameters from `providers.yml`

### Additional contract requirements

The global response exposes the common queryables `id`, `collection`, `geometry`, `bbox`, and `datetime`. It may also expose `ids`, but it does not include properties that are specific to an individual collection or provider.

Both endpoints return queryables documents following the linked STAC queryables documentation: each document is a JSON Schema using the JSON Schema Draft 2019-09 identifier, describes an object through `type` and `properties`, and has a non-empty `$id`. Each entry in `properties` is itself a JSON Schema definition.
