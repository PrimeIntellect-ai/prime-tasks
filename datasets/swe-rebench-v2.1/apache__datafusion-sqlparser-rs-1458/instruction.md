`EXPLAIN QUERY PLAN` fails to parse (sqlite)
## problem
queries with [explain query plan](https://sqlite.org/eqp.html) fail when using the sqlite dialect

## example
query:
```sql
select * from "sensor_data"
```

error:
```sh
sql parser error: Expected: end of statement, found: plan at Line: 1, Column: 15
```

### Additional contract requirements

- The `Statement::Explain` variant of the `Statement` enum carries an additional public boolean field `query_plan`. It is `true` for `EXPLAIN QUERY PLAN ...` statements and `false` for ordinary `EXPLAIN ...` statements.
- An `EXPLAIN QUERY PLAN ...` statement renders back to SQL that includes the `QUERY PLAN` keywords (for example, `EXPLAIN QUERY PLAN SELECT ...`).
