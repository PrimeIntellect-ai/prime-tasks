Need to maintain keyword list
I think the most important characteristic of "parse-unparse" is that it never changes the semantics of the query, but "parse-unparse" can break the semantics of the query.

`(*ast.Ident).SQL()` quote identifiers only when the identifier is keyword using [`QuoteSQLIdent`](https://github.com/cloudspannerecosystem/memefish/blob/9ec8ab98a6d7c7bcdbf61ac899e23b6d76f97f05/token/quote.go#L40-L52).

```
$ go run ./tools/parse --mode query 'SELECT 1 AS `SELECT`'
...
--- SQL
SELECT 1 AS `SELECT`
```

There are bad cases.

```
$ go run ./tools/parse --mode query 'SELECT 1 AS `IF`'
--- SQL
SELECT 1 AS IF
```

It is not valid query.

```
spanner> SELECT 1 AS IF;
ERROR: spanner: code = "InvalidArgument", desc = "Syntax error: Unexpected keyword IF [at 1:13]\\nSELECT 1 AS IF\\n            ^"
```

So, memefish must maintain `token.Keywords` in keywords.go.

It seems that the current diff is `GRAPH_TABLE` and `IF`.

```
--- keywords-in-go.txt  2024-09-28 00:12:47
+++ keywords.txt        2024-09-28 00:01:00
@@ -34,11 +34,13 @@
 FOR
 FROM
 FULL
+GRAPH_TABLE
 GROUP
 GROUPING
 GROUPS
 HASH
 HAVING
+IF
 IGNORE
 IN
 INNER
```

### Additional contract requirements

- An `IF(cond, true_result, else_result)` expression parses to a public `*ast.IfExpr` value in package `ast`; it is no longer parsed as a call expression.
- `ast.IfExpr` is an expression node with the exported fields `If token.Pos` (the position of the `IF` keyword), `Rparen token.Pos` (the position of the closing `)`), `Expr Expr` (the condition), `TrueResult Expr` (the value when the condition is true) and `ElseResult Expr` (the value when the condition is false).
- `(*ast.IfExpr).SQL()` serialises the expression as `IF(<cond>, <true>, <else>)`.
