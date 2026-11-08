Add support for fetching catalog queryables
Implement API for getting queryables properties as defined in https://github.com/radiantearth/stac-api-spec/blob/master/fragments/filter/README.md#queryables, for the STAC catalogs that support  additional data driven queriables.

### Additional contract requirements

A supporting STAC catalog can be queried through the public `Client.get_queryables()` method. The returned schema includes a `properties` mapping containing the catalog queryable fields.
