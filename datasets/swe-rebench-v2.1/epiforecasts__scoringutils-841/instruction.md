Make the output of `get_duplicates()` easier to work with
The function `get_duplicates()` returns all instances of duplicate forecasts. For example:

```
ex <- data.table::copy(example_quantile)
ex <- rbind(ex, ex[1000:1002])
duplicates <- get_duplicate_forecasts(ex)
duplicates
```

The output can be a bit overwhelming, in particular, if there are lots of duplicates. Things that could help:
- sorting the data.table such that duplicate rows are directly next to each other. This is probably really all it takes
- doing something similar like `get_forecast_counts()`, where we show the number of duplicates for a single forecast unit.

This could be as simple as this:
```
ex <- data.table::copy(example_quantile)
ex <- rbind(ex, ex[1000:1110])
duplicates <- get_duplicate_forecasts(ex)
[HIDDEN]
```

### Additional contract requirements

- The public function is `get_duplicate_forecasts(data, counts = FALSE)`, where `data` is a data.frame as used by `score()`.
- With `counts = FALSE` (the default), the function returns all rows that are duplicates, preserving the original columns. Rows belonging to the same duplicate forecast group must be adjacent in the output.
- With `counts = TRUE`, the function returns one row per forecast unit with an integer column `n_duplicates` giving the number of duplicate rows belonging to that unit.
