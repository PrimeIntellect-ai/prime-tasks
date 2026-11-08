FluxQueryResult: support reordering of annotations
This is a continuation of issues #110 and #123.
FluxQueryResult requires that the _datatype_ annotation is the first now.
It has to support  different order of annotations

### Additional contract requirements

The `#datatype`, `#group` and `#default` annotations may appear in any order.

When parsing fails, `QueryTableResult.Err()` must return an error whose message is exactly one of:

- `parsing error, annotations not found` when the column-name row is reached without any preceding annotation row.
- `parsing error, datatype annotation not found` when annotation rows are present but no `#datatype` annotation was found.
- `parsing error, row has different number of columns than the table: <rowColumns> vs <tableColumns>` when a data row has a different number of columns than the table, where `<rowColumns>` is the number of columns in the row and `<tableColumns>` is the number of columns in the table.
