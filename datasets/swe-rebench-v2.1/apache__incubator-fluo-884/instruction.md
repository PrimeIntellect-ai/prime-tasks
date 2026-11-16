Add stream support to Scanners
It would be really nice if the fluo scanners had methods to return java streams.

### Additional contract requirements

- `CellScanner` provides a `stream()` method returning `Stream<RowColumnValue>` over its cell elements.
- `ColumnScanner` provides a `stream()` method returning `Stream<ColumnValue>` over its column-value elements.
- `RowScanner` provides a `stream()` method returning `Stream<ColumnScanner>` over its row elements.
