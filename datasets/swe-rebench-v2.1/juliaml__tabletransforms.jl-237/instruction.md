Add `StdFeats` transform to standardize features
The `StdFeats` will apply the `ZScore` transform the the `Continuous` columns of a table. In the future it might do something else with other scientific types.

### Additional contract requirements

- `StdFeats` is a public transform type exported from `TableTransforms` and constructed with no arguments as `StdFeats()`.
- `apply(::StdFeats, table)` returns a pair `(new_table, cache)`. `new_table` is a table of the same type as the input table in which every `Continuous` column is standardized to zero mean and unit standard deviation and every other column is left unchanged. `cache` is the value accepted by `revert` to undo the transformation.
- `revert(::StdFeats, new_table, cache)` returns a table of the same type as the input table with the original column values restored.
- `isrevertible(::Type{StdFeats})` returns `true`.
- The compact display of a `StdFeats` instance is `"StdFeats()"`; its plain-text display is `"StdFeats transform"`.
