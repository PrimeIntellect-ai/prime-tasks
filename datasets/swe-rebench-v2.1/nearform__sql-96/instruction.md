bug: wrong character for IN condition
Given this example, it generates an invalid SQL query:

```js
const SQL = require('@nearform/sql')

const ids = [1, 2, 3]
const name = 'foo'
const inIds = SQL.glue(
  ids.map((id) => SQL`${id}`),
  ' , '
)

const condition = SQL`tsd.id IN (${inIds})`

const filters = [
  condition,
  SQL`tsd.name = ${name}`, //
]

const query = SQL`
    SELECT tsd.*
      FROM data tsd
    WHERE ${SQL.glue(filters, ' AND ')}
  `

console.log(query.sql)
console.log(query.values)
```

The output is the following. Note the `)?tsd.name` section:

```
SELECT tsd.*
FROM data tsd
WHERE tsd.id IN (? , ? , ?)?tsd.name = ?
[ 1, 2, 3, 'foo' ]
```

The workaround I found is switching the `filters`'s items produces the right SQL statement:

```
SELECT tsd.*
FROM data tsd
WHERE tsd.name = ? AND tsd.id IN (? , ? , ?)
[ 'foo', 1, 2, 3 ]
```
