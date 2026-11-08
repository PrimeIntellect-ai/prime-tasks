Add support for named arguments in SQLMesh macros
There is no clean way to skip optional arguments in macros today. For example, if we want to specify an `except` value for the `@STAR` [macro](https://sqlmesh.readthedocs.io/en/latest/concepts/macros/sqlmesh_macros/#star), we also need to specify an alias, otherwise the SQL arguments won't map to the correct python arguments.

One way to address this is to add support for named arguments. We could use `PropertyEQ` (ie. `:=`) to achieve this, so the `@STAR` issue would be resolved by simply doing:

```sql
SELECT @STAR(foo, except := [a, b, c])
```
