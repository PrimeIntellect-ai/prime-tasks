`charset` and `collation` do not work for table columns
error from the `replicated-controller-0` pod:

```
{"level":"error","msg":"Error 1064: You have an error in your SQL syntax; check the manual that corresponds to your MySQL server version for the right syntax to use near 'character set latin1 collate latin1_danish_ci' at line 1"}
```

### Additional contract requirements

- When a column specifies a character set or collation, the generated MySQL column definition must place the `character set <charset>` and `collate <collation>` clauses before any `NOT NULL`/`NULL` and `DEFAULT` clauses. This ordering must hold both when adding a column and when modifying an existing column.
