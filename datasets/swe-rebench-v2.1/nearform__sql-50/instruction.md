Make quoteIdent safe
The `quoteIdent` function is currently unsafe as it only wraps a literal value with double quotes. It should be made safe my mimicking the behavior of the native PG quote_ident function.

https://doxygen.postgresql.org/ruleutils_8c.html#a30a0e11b313ae9c277420959cd655ac2
