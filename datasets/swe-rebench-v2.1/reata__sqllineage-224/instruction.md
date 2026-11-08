Table/Column Lineage Mixed up For Self Dependent SQL
```sql
INSERT OVERWRITE TABLE foo
SELECT col FROM foo
WHERE flag IS NOT NULL
```

```
Statements(#): 1
Source Tables:
    <default>.foo
    <default>.foo.col
Target Tables:
    <default>.foo
    <default>.foo.col
```

Column lineage is displayed by mistake here.
