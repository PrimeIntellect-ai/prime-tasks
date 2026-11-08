perf: avoid doing work when mapping ordered categorical to Enum
Currently, when mapping an ordered categorical to Enum, we call `tuple` on the categories, or even `to_pandas()` on the categories for cudf

This should be unnecessary, I think we should only compute the categories as a tuple when it becomes necessary:
- when inspecting `dtype.categories`
- when printing the dtype

### Additional contract requirements

When an ordered categorical is mapped to an Enum dtype, obtaining the dtype must not eagerly materialize its category values. The values are materialized only when the categories are inspected or the dtype is printed. For cudf categoricals, the categories must be available without converting them to pandas, including when they are inspected. The Enum exposes its categories in order and displays those categories when printed.
