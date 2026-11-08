Expressions not allowed in index creation statements
### SQLDelight Version

1.5.3

### SQLDelight Dialect

Android version 12

### Describe the Bug

DDL for creating an index with an expression like the following fails:

`CREATE INDEX test_idx ON tbl(field1, field2, coalesce(field3, field4, field5) DESC);`

The reported error:

```
test.sq line 44:89 - ')', ',', ASC, COLLATE or DESC expected, got '('
44  CREATE INDEX test_idx ON tbl(field1, field2, coalesce(field3, field4, field5) DESC);
```

### Stacktrace

_No response_
