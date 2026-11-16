Use --external-options to pass in CSV column indices for package name and license name
For now, CSV column indices for package name/license name are hardcoded.
That may require some manipulations with the external file before running the tool against it, which is far from ideal.
We need to move these indices to the `--external-options`, e.g.
```
{:package-name-column-index: 0, license-name-columnt-index: 1}
```

### Additional contract requirements

- The column indices are supplied through the `--external-options` CLI option as an EDN map, for example `--external-options '{:package-column-index 0 :license-column-index 3}'`.
- The option keys are `:package-column-index` (zero-based index of the package name column) and `:license-column-index` (zero-based index of the license name column).
- When an option is omitted, the defaults are `:skip-header true`, `:package-column-index 0` and `:license-column-index 1`.
- A requested column index that is out of range for a row yields `nil` for that field instead of raising an error.
