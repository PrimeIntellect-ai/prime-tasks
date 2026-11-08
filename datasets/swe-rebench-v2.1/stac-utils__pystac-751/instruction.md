Add a `stac_io` argument in `Catalog.save`?
It is nice how the STAC I/O has been refactored, with the possibility for the user to provide customised `StacIO` instances as argument to `StacObject.save_object` (or `ItemCollection.save_object`).

But shouldn't the catalog `Catalog.save` method also accept a `stac_io` argument to optionally specify the `StacIO` to recursively write out all children and items?

If you agree, I would be happy to contribute with a PR!
