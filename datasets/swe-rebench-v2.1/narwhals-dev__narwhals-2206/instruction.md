api: disallow `LazyFrame.select()`
`lf.select()` is a bit problematic and varies a bit across backends, as for duckdb/sqlframe it seems we don't have a way to return a table with 0 rows and 0 columns

I propose to just require that at least one expression be passed to `LazyFrame.select`, problem solved
