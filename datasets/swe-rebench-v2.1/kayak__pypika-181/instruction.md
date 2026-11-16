Subquery as select field
Is it possible to use subquery in the select clause? Something like this
```sql
SELECT
  table_a.id,
  table_a.name,
  (
    SELECT table_b.name
    FROM table_b
    WHERE
      table_b.id=table_a.id_table_b
  )
FROM table_a
```

### Additional contract requirements

A subquery used as a selected field can reference a field from the enclosing query in its condition. When the reference is unqualified, the generated SQL must preserve that field reference inside the parenthesized subquery so SQL name resolution can resolve it against the enclosing query.
