Add support for parametrized datetime column in MySQL
Using the following spec:

``` yaml
apiVersion: schemas.schemahero.io/v1alpha4
kind: Table
metadata:
  name: test-table
spec:
  database: mydb
  name: test_table
  schema:
    mysql:
      columns:
      - name: created_at
        type: datetime (3)
        constraints:
          notNull: true
```

`schemahero plan` produces the following error:

```
Error: failed to build column statements: failed to create alter column statement: unknown column type. cannot validate column type "datetime (3)"
failed to build column statements: failed to create alter column statement: unknown column type. cannot validate column type "datetime (3)"
```

### Additional contract requirements

- MySQL column types `datetime (<precision>)` and `timestamp (<precision>)` must be supported for precisions from 0 through 6 inclusive. Schema planning and generated DDL must retain the declared type and precision, using the canonical form `datetime (<precision>)` or `timestamp (<precision>)`.
- A declaration with an out-of-range precision must be rejected with an error identifying the type and requested precision. For example, the error message for `datetime (7)` must include `invalid datetime precision 7`, and for `timestamp (7)` it must include `invalid timestamp precision 7`.
