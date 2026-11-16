Union queries with `+` seems to be broken when used for more than 2 queries
**Example**
```
from pypika import Tables, Query
a,b,c = Tables('a', 'b', 'c')
qa=Query.from_(a).select(a.a, 'name')
qb=Query.from_(b).select(b.b, 'name')
qc=Query.from_(c).select(c.c, 'name')

qa+qb
str(qa+qb)  # 1)
qa+qb+qc
str(qa+qb+qc)  # 2)
```

this used to output
1) `'(SELECT "a","name" FROM "a") UNION (SELECT "b","name" FROM "b")'`
2) `'((SELECT "a","name" FROM "a") UNION (SELECT "b","name" FROM "b")) UNION (SELECT "c","name" FROM "c")'`

**Issue**
Now, it out puts for
1) still the same but for
2) `'(SELECT "a","name" FROM "a") UNION (SELECT "b","name" FROM "b")+SELECT "c","name" FROM "c"'`

`qa+qb` is a `UnionQuery`, but `qa+qb+qc` is an `ArithmeticExpression`

if my bisect was correct, this was introduced in commit `3e850da1fdca72e0766a4e7b5bceceb88a97acaa`

**work around**
using `.union()` instead of the `+` sign still works fine

### Additional contract requirements

- For a four-query chain formed with `+`, `str(...)` must be exactly `(SELECT "foo" FROM "abc") UNION (SELECT "bar" FROM "efg") UNION (SELECT "baz" FROM "hij") UNION (SELECT "faz" FROM "lmn")`.
- The object produced by `+`, including when more than two queries are chained, must be the same kind of union query object that `.union()` produces, and must not be an arithmetic expression.
- A three-query chain formed with `+` must combine all three queries with two `UNION` operators. Its parenthesization is not prescribed; the nested form shown in the historical output is descriptive, not a formatting requirement.
