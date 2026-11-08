with_defaults breaks on long input
```
names(lintr::with_defaults(
  default = list(),
  lintr::undesirable_function_linter(c(
    detach = paste(
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    )
  ))
))
# [1] "lintr::undesirable_function_linter\n    \"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\")))"
```

Obviously a bit contrived but actually got bit by this in a case where there are a few long comments intervening & several functions with long messages.

Something goes wrong with the `eval(substitute())` approach at some number of characters. The issue is surmountable but [HIDDEN].

### Additional contract requirements

- `with_defaults()` must derive the correct automatic name for a supplied linter expression even when the expression is very long or spans multiple lines. In the shown example, the name should be `lintr::undesirable_function_linter`.
