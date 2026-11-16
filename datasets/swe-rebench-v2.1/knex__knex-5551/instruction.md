orderBy inconsistency with positional (numeric) arguments
# Environment

Knex version: 2.4.2
Database + version: Postgres 14.6
OS: MacOS Ventura

# Bug

```
knex('t').select('a', 'b', 'c').orderBy(['a', 'b']).orderBy('c').toString();
  --> select "a", "b", "c" from "t" order by "a" asc, "b" asc, "c" asc    // okay
knex('t').select('a', 'b', 'c').orderBy([1, 2]).orderBy(3).toString();
  --> select "a", "b", "c" from "t" order by 3 asc    // oops, where did 1 and 2 go?
```

Problem: When using positional order-by, the `.orderBy([1, 2])` form is ignored, whereas `.orderBy(1).orderBy(2)` works fine.
