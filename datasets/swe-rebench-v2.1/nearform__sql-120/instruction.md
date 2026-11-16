Value array support
Starting from the following example, I would like to simplify the `query2` code like the `query` is.

The `query` output leads to an `"[object object]"` string replacement, I think it would be good to support an "auto-glue" option to avoid the `SQL.glue` statement for these simple tasks.

```
const SQL = require('@nearform/sql')

const ids = [1, 2, 3]

const query = SQL`SELECT * FROM table WHERE id IN (${ids})`
console.log(query.sql)
console.log(query.values)
// SELECT * FROM table WHERE id IN (?)
// [ [ 1, 2, 3 ] ]

const query2 = SQL`SELECT * FROM table WHERE id IN (${SQL.glue(
  ids.map((id) => SQL`${id}`),
  ','
)})`
console.log(query2.sql)
console.log(query2.values)
// SELECT * FROM table WHERE id IN (?,?,?)
// [ 1, 2, 3 ]

```

### Additional contract requirements

Arrays can be expanded into a SQL fragment by passing them to `SQL.map(array, mapperFunction)` and interpolating the result into a query. For each array item, use the item itself when no mapper is supplied, or the mapper's result when one is supplied. Emit one comma-separated SQL placeholder per item, with bound values in a flat list in input order.
