Better error messages for invalid SQL in sql blocks
Since we are wrapping an exception, and have no idea what the error message in the exception looks like, we just preface it with "schema error", but that ends up making it hard to understand what is going on ....

```
Schema error: Syntax error: Unexpected string literal 'bigquery-public-data.san_francisco.`sfpd_incidents
```

and then the sql interpreter gives back a line number, but it is the line in the SQL Query ... I'm thinking

```
SQL Execution Error in SQL block
    Syntax error: Unexpected string literal 'bigquery-public-data.san_francisco.`sfpd_incidents
```
