Inserting empty array and document into boolean field
If I insert an empty array or an empty document into a boolean field, I would expect that the value of that field will be `false`. Exactly the same way as with empty strings.

What do you think?

```sql
genji> CREATE TABLE test(a bool, b bool, c bool);
genji> INSERT INTO test VALUES {a: "", b: [], c: {}};
genji> SELECT * FROM test;
{
  "a": false,
  "b": true,
  "c": true
}
```
