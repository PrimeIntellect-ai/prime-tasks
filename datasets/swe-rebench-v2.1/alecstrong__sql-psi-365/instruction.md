Allow functions containing keywords instead of commas
Dialect: [HSQLDB](http://hsqldb.org/doc/guide/builtinfunctions-chapt.html), [MySQL](https://dev.mysql.com/doc/refman/8.0/en/string-functions.html#function_substring), [PostgreSQL](https://www.postgresql.org/docs/9.1/functions-string.html)

Some functions allow replacing the commas in an argument list with keywords.

Failing SQL:

```sql
SELECT substring('Thomas' from 2 for 3)
```
