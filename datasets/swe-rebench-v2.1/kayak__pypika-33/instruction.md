Some Vertica 'UNION ALL' queries need brackets
Currently PyPika creates union queries as `query1 UNION ALL query2`.

This works fine in most cases, e.g.

```
SELECT id FROM myTable
UNION ALL
SELECT id FROM myTable
```

At least for Vertica though, there are some queries where this throws an error, e.g.:

```
SELECT id FROM myTable ORDER BY id ASC
UNION ALL
SELECT id FROM myTable ORDER BY id ASC
```

The fix is as simple as adding brackets:

```
(SELECT id FROM myTable ORDER BY id ASC)
UNION ALL
(SELECT id FROM myTable ORDER BY id ASC)
```

### Additional contract requirements

- `Query.union(other)` and the `+` operator must render each SELECT operand in parentheses, producing exactly `(SELECT "foo" FROM "abc") UNION (SELECT "bar" FROM "efg")` for the simple queries above.
- `Query.union_all(other)` and the `*` operator must render each SELECT operand in parentheses, producing exactly `(SELECT "foo" FROM "abc") UNION ALL (SELECT "bar" FROM "efg")` for the simple queries above.
- Ordered SELECT operands must also be bracketed, for example `(SELECT "id" FROM "myTable" ORDER BY "id" ASC) UNION ALL (SELECT "id" FROM "myTable" ORDER BY "id" ASC)`.


- When both SELECT operands use `orderby()` without an explicit direction, `union_all()` and `*` must render exactly `(SELECT "foo" FROM "abc" ORDER BY "foo") UNION ALL (SELECT "bar" FROM "efg" ORDER BY "bar")` for those queries.
