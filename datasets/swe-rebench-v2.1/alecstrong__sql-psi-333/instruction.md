Hsql named arguments
Dialect: H2

failing sql: wherever named arguments are used, eg:

```sql
SELECT * FROM tablename WHERE columnname = :arg;
```

Error:
```
<binary like operator real>, <column expr real>, <compound operator real>, <exists expr real>, <expr>, <literal value real>, '?', BETWEEN, GROUP, IN, LIMIT, ORDER, RAISE or id expected, got ':'
```
