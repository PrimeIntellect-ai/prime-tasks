prevent authentication during search preparation
Following https://github.com/CS-SI/eodag/pull/753, authentication is performed for all providers needing auth for search in `_prepare_search()`.

Only auth plugin should be passed as argument, and authentication should be performed before search for the given provider.

### Additional contract requirements

- `EODataAccessGateway._prepare_search(self, start=None, end=None, geom=None, locations=None, provider=None, **kwargs)` in module `eodag.api.core` returns a tuple `(search_plugins, prepared_kwargs)`, where `search_plugins` is the list of search plugin instances selected for the query and `prepared_kwargs` is the dict of prepared search keyword arguments.
- The prepared search keyword arguments dict must not contain the former `search_plugins` or `auth` keys.
