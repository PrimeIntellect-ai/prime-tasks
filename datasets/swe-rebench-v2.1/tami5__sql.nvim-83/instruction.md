table.each accept function as first arg
support table.each/map to accept function as first argument and query as second argument and vice-versa

### Additional contract requirements

Both `each` and `map` accept the callback as the first argument and an optional query as the second argument, as well as the query first and callback second. When the query is omitted, they operate on all rows without query filters. The order in which selected rows are visited or returned is not specified.
