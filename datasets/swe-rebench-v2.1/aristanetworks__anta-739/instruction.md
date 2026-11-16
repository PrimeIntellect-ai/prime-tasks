Support JSON catalog
With a large catalog, loading from YAML in Python can be very slow.

### Additional contract requirements

- Test catalogs can be loaded from JSON in addition to YAML.
- `AntaCatalog.parse(filename, file_format="yaml")` in module `anta.catalog` accepts a `file_format` argument whose value is either `"yaml"` or `"json"` (default `"yaml"`), and raises `ValueError` when any other value is supplied.
- `AntaCatalog.parse` raises `ValueError` when the catalog file cannot be parsed, for example when a JSON catalog is malformed.
- The `anta nrfu` command accepts a `--catalog-format` option whose value is either `yaml` or `json` (default `yaml`). The same value can be supplied through the `ANTA_CATALOG_FORMAT` environment variable. The catalog is loaded using the selected format, and an unsupported value is rejected with a usage error.
