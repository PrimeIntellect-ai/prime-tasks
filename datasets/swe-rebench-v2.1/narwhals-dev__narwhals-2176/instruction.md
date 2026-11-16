api: use `large_string` / `large_list` when converting Narwhals types -> PyArrow?
Currently we convert `nw.String` to pyarrow string. Polars would convert `pl.String` to pyarrow large_string. We should probably be doing the same?

### Additional contract requirements

- `nw.concat_str(*exprs, separator="", ignore_nulls=False)` returns an `Expr`. When evaluated on PyArrow data, the resulting column's Arrow type is `large_string` if any input column is `large_string`, and `string` otherwise.
- `nw.concat_str` raises an error when a supplied column cannot be represented as a string.
- `nw.lit(value, dtype=None)` returns an `Expr`. A string literal produces an Arrow `string` column, and the general mapping of `nw.String` to PyArrow remains `string`. A literal whose value is a PyArrow `large_string` scalar produces an Arrow `large_string` column.


- Selecting `nw.lit(...)` without an alias names the output column `literal`.
