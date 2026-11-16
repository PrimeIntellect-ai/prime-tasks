REFACTOR: Provide overridable method for estimated row count
We have a number of properties in BaseQueryCompiler to direct and restrict the calls to axis=0 queries, but we do not have a method where an estimated row count can be retrieved. Initially this will only be used for the auto switch code where the row count is a necessary part of figuring out if a dataset can be moved. The method is internal but overridable by sub-classes. We can decide later if we want to make it a public method.

### Additional contract requirements

- `BaseQueryCompiler` must provide an internal, overridable `_max_shape(self)` method that returns a `(estimated_max_rows, estimated_max_columns)` tuple. By default, these values are the current row and column counts. The estimated row count is the first tuple element.
