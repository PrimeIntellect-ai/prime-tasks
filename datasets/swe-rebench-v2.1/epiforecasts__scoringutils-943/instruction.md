Handling asymmetric intervals
EDIT: we only need to change `wis`, since `interval_coverage()` was changed in #924 and `interval_coverage_deviation()` was deleted for now.

We should handle asymmetric intervals consistently. Consider

```
  asymm <- example_quantile[!quantile_level > 0.6]
```

Currently:
- `interval_coverage()` and `interval_coverage_deviation()` throw a warning (#924 updates this to an error)
- `wis()` silently drops incomplete intervals (which seems bad)

`interval_coverage()`, which only handles a single interval, should error (done in  https://github.com/epiforecasts/scoringutils/pull/924)

Options for `interval_coverage_deviation()` and `wis()`
- error, if any intervals are not complete
- drop incomplete intervals and raise a warning
- introduce an `na.rm` option (default = `FALSE`). If TRUE, silently drop incomplete intervals. If `FALSE`, error


---

Example: `wis()`

The WIS requires intervals that are symmetric (in terms of the quantile levels provided) around the median. If that's not the case, `wis()` silently drops those.

Consider the following:

```
  # asymmetric intervals
  asymm <- example_quantile[!quantile_level > 0.6]
  inner <- example_quantile[quantile_level %in% c(0.4, 0.45, 0.5, 0.55, 0.6)]
  a <- score(inner) |>
    summarise_scores(by = "model")

  b <- score(asymm) |>
    summarise_scores(by = "model")

  a$wis == b$wis
```

### Additional contract requirements

For WIS, incomplete prediction intervals cause an error by default. When `na.rm = TRUE`, incomplete intervals are silently dropped.
