bug: `df.filter(c=nw.col('a'))` gives incorrect result for pandas and unclear error message for duckdb
the keywords-syntax in `filter` is meant to be used with literals, not with expressions. e.g. `filter(c=3)` is shorthand for `filter(nw.col('c')==3)`

Can we produce an informative error message, with a hint, if someone writes `df.filter(c=nw.col('a'))`?
`

### Additional contract requirements

The keyword-syntax in `filter` accepts both literal values and `Expr` values as constraints. A constraint `name=value` is interpreted as `col(name) == value`; when `value` is an `Expr`, the comparison is evaluated against that expression. For example, `df.filter(a=nw.col('b') // 3)` keeps the rows where `a == b // 3`. The resolution adopted for the request above is to support expression-valued constraints rather than to raise an error.
