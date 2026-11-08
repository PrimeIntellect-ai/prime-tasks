Support analytic queries for Vertica and Oracle
https://my.vertica.com/docs/7.1.x/HTML/Content/Authoring/SQLReferenceManual/Functions/Analytic/AnalyticFunctions.htm

Add support for analytical functions and queries using PARTITION OVER

### Additional contract requirements

- The analytic function wrappers are provided by the `pypika.analytics` module (importable as `analytics` from `pypika`): `Rank()`, `NTile(n)`, `FirstValue(*terms)`, `LastValue(*terms)`, `Median(term)`, `Avg(term)` and `StdDev(term)`. They render as the SQL functions `RANK()`, `NTILE(n)`, `FIRST_VALUE(...)`, `LAST_VALUE(...)`, `MEDIAN(...)`, `AVG(...)` and `STDDEV(...)`.
- Each of these functions can be given a partition with `.over(*terms)` and an ordering with `.orderby(*terms)`. Both accept any number of column terms, return the function so that calls can be chained in either order, and render as `OVER(PARTITION BY ... ORDER BY ...)`. The partition and ordering parts are each present only when they were given. Multiple terms are rendered comma-separated in the order given, without spaces, as the library renders other lists. When neither a partition nor an ordering is given, no OVER clause is rendered.
- `FirstValue` and `LastValue` accept one or more terms. `.ignore_nulls()` renders `IGNORE NULLS` after the arguments inside the function call.
- Analytic queries built with `VerticaQuery` and `OracleQuery` render the same SQL as the default `Query` class.
- When a query joins tables, columns used in analytic partitions and orderings are rendered table-qualified (for example `"abc"."foo"`).
