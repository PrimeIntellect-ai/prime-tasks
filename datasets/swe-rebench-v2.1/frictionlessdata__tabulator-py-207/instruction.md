Get sheet in Excel/OpenOffice by name
Is there a way to get a sheet by name rather than number?

### Additional contract requirements

- `tabulator.Stream` accepts a `sheet` option that is either a 1-based integer index or the exact name of a worksheet, for Excel (xls/xlsx) and OpenOffice (ods) spreadsheets.
- Opening a stream for a worksheet that does not exist raises `tabulator.exceptions.SourceError`. The error message includes `sheet "3"` when `sheet=3` is requested and `sheet "not-existent"` when `sheet='not-existent'` is requested.
