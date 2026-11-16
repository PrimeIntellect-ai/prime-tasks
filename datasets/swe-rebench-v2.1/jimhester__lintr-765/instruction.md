Spurious snake_case error when using `$` in assignment
```
get_deseq_dataset.R:60:17: style: Variable and function name style should be snake_case.
        tx2gene$TXNAME <- sub("^transcript:", "", tx2gene$TXNAME)
                ^~~~~~
```

### Additional contract requirements

- The linter under test is `object_name_linter()`; its default styles are `c("snake_case", "symbols")`.
- Its lint message is exactly `Variable and function name style should be snake_case or symbols.`
- In an assignment whose target uses `$` (for example `tx2gene$TXNAME <- ...`), only the leftmost name is an assignment target and is checked; the names after `$` are not checked.
