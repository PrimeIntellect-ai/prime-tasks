Support current spec of aggregate function calls
Aggregate function calls have several optional clauses.
https://cloud.google.com/spanner/docs/reference/standard-sql/aggregate-function-calls
```
function_name(
  [ DISTINCT ]
  function_arguments
  [ { IGNORE | RESPECT } NULLS ]
  [ HAVING { MAX | MIN } having_expression ]
)

```
I think
* `{IGNORE | RESPECT } NULLS`
* `HAVING {MAX | MIN}`
are missing in memefish.

```
$ go run ./tools/parse --mode statement 'SELECT ARRAY_AGG(x IGNORE NULLS)'
2024/08/21 18:08:23 syntax error::1:20: expected token: ), but: IGNORE

  1:  SELECT ARRAY_AGG(x IGNORE NULLS)
                         ^~~~~~
exit status 1
```

```
$ go run ./tools/parse --mode statement 'SELECT ANY_VALUE(year HAVING MAX inches)'
2024/08/21 18:07:17 syntax error::1:23: expected token: ), but: HAVING

  1:  SELECT ANY_VALUE(year HAVING MAX inches)
                            ^~~~~~
exit status 1
```

### Additional contract requirements

- An aggregate function call accepts an optional `IGNORE NULLS` or `RESPECT NULLS` clause after its arguments, and an optional `HAVING MAX <expr>` or `HAVING MIN <expr>` clause. Both clauses may appear in one call, with the NULLS clause before the HAVING clause. Both forms must parse, and the parsed call must keep both clauses.
- The parsed call node stores the NULLS clause in its `NullHandling` field and the HAVING clause in its `Having` field. Each field is nil when the clause is absent.
- `NullHandling` holds a `*ast.IgnoreNulls` or a `*ast.RespectNulls`. Both have position fields `Ignore` or `Respect` for the keyword (`IGNORE` or `RESPECT`) and `Nulls` for the `NULLS` keyword.
- `Having` holds a `*ast.HavingMax` or a `*ast.HavingMin`. Both have a position field `Having` for the `HAVING` keyword and an `Expr` field holding the parsed expression.
- Converting a parsed call back to SQL yields a single line in which the clauses are separated by single spaces, for example `ARRAY_AGG(inches RESPECT NULLS HAVING MAX year)`.
- `COUNT(*)` is not affected by these clauses.
