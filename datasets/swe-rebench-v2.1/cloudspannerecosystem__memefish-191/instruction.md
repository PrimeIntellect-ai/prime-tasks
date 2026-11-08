Incompatibility: ANALYZE statement
This incompatibility is detected by #90.

## Spec

https://cloud.google.com/spanner/docs/reference/standard-sql/data-definition-language#analyze-statistics

## Reproducing input
```
ANALYZE
```

## Current behavior
```
syntax error:testdata/combined.test:2:1: expected pseudo keyword: ALTER, DROP, but: ANALYZE

  2:  ANALYZE
      ^~~~~~~
```

### Additional contract requirements

- A standalone `ANALYZE` statement must be accepted by both the DDL parser and the general statement parser, and it must render back to the SQL text `ANALYZE`.
- The parsed statement is represented by an `ast.Analyze` node that records the position of the `ANALYZE` keyword in its `Analyze` field, following the convention of the other statement nodes in the `ast` package.
