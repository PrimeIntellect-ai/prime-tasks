appending rows when there are dynamic columns
At the moment we cannot add rows (using append, rpush, lpush) when there is already a dynamic column: a function object can be added at the appropriate place in the row, but unlike a normal dynamic column it will not be executed.

### Additional contract requirements

- When adding a row with `append`, `rpush`, or `lpush`, omitted dynamic-column values are calculated from the row by their column functions.
- For any of these row-addition methods, values may be supplied for all dynamic columns, preserving the supplied values, or for none; supplying values for only some dynamic columns raises `tablib.InvalidDimensions`.
