Assets are not prefixed with `requests_pathname_prefix`.
The assets files should be prefixed with the `requests_pathname_prefix` like other resources.

### Additional contract requirements

- Add a public function `get_asset_path(requests_pathname, routes_pathname, asset_path)` in module `dash._utils`. It returns the URL path for the given asset filename, prefixed with the request pathname. For example, `get_asset_path('/', '/', 'reset.css')` returns `/assets/reset.css`, `get_asset_path('/requests/', '/', 'reset.css')` returns `/requests/assets/reset.css`, and `get_asset_path('/requests/routes/', '/routes/', 'reset.css')` returns `/requests/assets/reset.css`.
