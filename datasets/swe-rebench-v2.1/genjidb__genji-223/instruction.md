IN doesn't work with parentheses
```
genji> select 1 IN (1, 2, 3);
found ,, expected ) at line 1, char 15
genji>
```

```
sqlite> select 1 IN (1, 2, 3);
1
sqlite>
```

Other example:

```sql
SELECT * FROM foo WHERE a IN (1, 2, 3)
```

This is a valid SQL expression, but currently, we only support this:

```sql
SELECT * FROM foo WHERE a IN [1, 2, 3]
```

This might be more complex than just parsing parentheses when we are in an IN operator.

I think we need to parse parentheses in two different ways:

### Single expression: `(expr)`

Example:

```sql
SELECT (1);
-> 1
SELECT (1 + 1);
-> 2
```

This is already supported, the parser [returns](https://github.com/genjidb/genji/blob/9da693665fe93d3fcfdffe3312a48712fc40023f/sql/parser/expr.go#L204-L212) an [expr.Parentheses](https://github.com/genjidb/genji/blob/9da693665fe93d3fcfdffe3312a48712fc40023f/sql/query/expr/expr.go#L127:6) expression.

### List of expressions: `(expr, expr, ...)`

Example:

```sql
SELECT (1, 2);
-> [1, 2]
SELECT (1 + 1, 3 > 5);
-> [2, false]
```

[HIDDEN]

### Additional contract requirements

- Parenthesized comma-separated expressions with more than one element must be accepted as a list-valued expression. Each member is evaluated normally, and the list contains the resulting values in order (for example, `(1 + 1, 3 > 5)` yields `[2, false]`).
- The parenthesized list syntax must also be accepted on the right-hand side of `IN`, with the same membership behavior as the corresponding bracketed list.
- A parenthesized comma-separated expression list with more than one member is represented as an `expr.LiteralExprList`.
