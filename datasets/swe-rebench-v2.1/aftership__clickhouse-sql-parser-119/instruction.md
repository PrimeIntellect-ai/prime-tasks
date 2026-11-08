Accessing tuple in SELECT clause with dot notation yields error
Parsing `SELECT t.1 FROM test` yields:

```
        	            	line 0:9 <EOF> or ';' was expected, but got: "1"
        	            	SELECT t.1 FROM test
        	            	         ^
```

Link to fully working example: https://fiddle.clickhouse.com/abc5451d-1843-4659-b2f1-a13bf1cbb29d

As a workaround the `tupleElement` function works and `SELECT tupleElement(t, 1) FROM test` gets parsed properly, but for convenience I would appreciate tuple aliases in `SELECT` clauses with dot notation being supported.

### Additional contract requirements

- When parsed statements are serialized to JSON, a dot/index access expression (for example the `t.1` in `SELECT t.1 FROM test`) stores its left-hand operand under the key `"Object"` (rather than `"LeftExpr"`). This applies to every such expression, including the pre-existing tuple-access cases such as `tuple('a','b','c').3`.
