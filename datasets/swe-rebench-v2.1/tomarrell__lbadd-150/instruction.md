parser: select expression doesn't work
Try to parse `SELECT amount * price AS total_price FROM items`. This will throw a lot of errors, although the production

`SELECT result-column ...`

with `result_column` using the `expr` production, and `expr` using the `expr binary-operator expr` allows such a statement.
