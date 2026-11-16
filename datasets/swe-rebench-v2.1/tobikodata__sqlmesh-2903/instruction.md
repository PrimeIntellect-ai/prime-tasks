Using Macros in Navigation Functions with IGNORE NULLS
Hello there,

I can use a SQLMesh Macro with no issue in a navigation function like so:
```sql
@DEF(test, x -> x);

SELECT FIRST_VALUE(@test(x)) OVER (ORDER BY y) AS column_test
   , x
   , y
FROM test;
```

However, adding `IGNORE NULLS` after the Macro call:
```sql
@DEF(test, x -> x);

SELECT FIRST_VALUE(@test(x) IGNORE NULLS) OVER (ORDER BY y) AS column_test
   , x
   , y
FROM test;
```

I get a `Error: Macro variable '' is undefined.` error.
