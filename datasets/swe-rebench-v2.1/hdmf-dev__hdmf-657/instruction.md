Allow DynamicTableRegion.__getitem__ to take string column name
See https://github.com/NeurodataWithoutBorders/pynwb/issues/1193

It would be nice to be able to do `dtr['col1']` to get the column named 'col1' from the target table of `dtr`. This is a shortcut for `dtr.table['col1']`.

cc @bendichter

## Checklist

- [x] Have you ensured the feature or change was not already [reported](https://github.com/hdmf-dev/hdmf/issues) ?
- [x] Have you included a brief and descriptive title?
- [x] Have you included a clear description of the problem you are trying to solve?
- [x] Have you included a minimal code snippet that reproduces the issue you are encountering?
- [x] Have you checked our [Contributing](https://github.com/hdmf-dev/hdmf/blob/dev/docs/CONTRIBUTING.rst) document?
