Add support for snowflake cluster by expressions
```sql
CLUSTER BY (to_date(ts), coalesce(foo, 'bar'))
```
Failed with `ParserError("Expected: ), found: (`
https://docs.snowflake.com/en/user-guide/tables-clustering-keys#defining-a-clustering-key-for-a-table

We need to extend/change CreateTable cluster_by type from
```rust
[HIDDEN]
```
to
```rust
[HIDDEN]
```
This allows statements like CLUSTER BY (to_date(start_tstamp)) to be parsed correctly.

### Additional contract requirements

- `CLUSTER BY` must accept full expressions, not only plain identifiers, in both
  the parenthesized form (`WrappedCollection::Parentheses`) and the
  unparenthesized form (`WrappedCollection::NoWrapping`). For example both
  `CLUSTER BY (a, b, my_func(c))` and `CLUSTER BY my_func(c), y` must parse,
  with the function call represented as an `Expr::Function` element of the
  clustering list.
