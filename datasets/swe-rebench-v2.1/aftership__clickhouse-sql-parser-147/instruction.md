Failed to parse query with $ in column name
The following query throws error **_line 0:30 <EOF> or ';' was expected, but got: "$"_**

```sql
SELECT service$$name FROM test_table
```

On the other hand, this works
```sql
SELECT `service$$name` FROM test_table
```

When we run `SELECT service$$name FROM test_table`, CH automatically add "``" to such columns. The parser should recognise that and not throw an error.

### Additional contract requirements

- Formatting `SELECT $abc, a$$bc, abc$$;` must produce `SELECT $abc, a$$bc, abc$$;`.
