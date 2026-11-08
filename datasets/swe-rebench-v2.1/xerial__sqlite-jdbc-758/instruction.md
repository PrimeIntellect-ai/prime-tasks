Connection.getMetaData().getColumns returns wrong/fixed values for column data type details
Using the `ResultSet` returned by `Connection.getMetaData().getColumns()` returns wrong values for the size of the column.

Especially these values are wrong:
- `COLUMN_SIZE` (fixed `10`)
- `DECIMAL_DIGITS` (fixed `2000000000`)

The `DATA_TYPE` is correct, but the client is unable to detect the size of the column or the precision of floating point values.

_Example:_
I have a table with this column: `ORIENTATION REAL(6,3)`

This is what I get:

- `COLUMN_NAME`=`"ORIENTATION"` (correct)
- `TYPE_NAME`=`"REAL(6,3)"` (correct)
- `DATA_TYPE`=`6` (correct, is `java.sql.Types.FLOAT`)
- `COLUMN_SIZE`=`2000000000` (wrong, should be `9`?, `6+3`)
- `DECIMAL_DIGITS`=`10` (wrong, should be `3`)

The cause for this can be found [HIDDEN] and [HIDDEN].

I just did not found a simple fix, so I add this issue instead of a pull request 😉

### Additional contract requirements

- For FLOAT columns without a declared scale and columns with no declared type, `getColumns()` must report `DECIMAL_DIGITS` as `10`.
- For columns without declared dimensions—including INTEGER columns, FLOAT columns, and columns with no declared type—`getColumns()` must report `COLUMN_SIZE` as `2000000000`.
- For a column with one declared dimension, `getColumns()` must report that value as `COLUMN_SIZE`. For dimensions `(p,s)`, it must report `p+s` as `COLUMN_SIZE`.
