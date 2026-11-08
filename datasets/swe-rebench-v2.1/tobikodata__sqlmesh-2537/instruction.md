Comments on `MODEL` properties are removed by `sqlmesh format`
For example:

```sql
MODEL(
  name foo.bar, -- my model is awesome
  kind VIEW,
);
SELECT * FROM foo_bar
```

Will produce

```sql
MODEL(
  name foo.bar,
  kind VIEW,
);
SELECT
  *
FROM foo_bar
```
