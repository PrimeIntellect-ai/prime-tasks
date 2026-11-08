check_equal_length fails when all inputs are of length 1
Running this
```
scoringutils::interval_score(true_values = 5,
                             lower = 4,
                             upper = 6,
                             interval_range = 95,
                             weigh = TRUE,
                             separate_results = FALSE)
```

gives

```
Error in check_equal_length(true_values, lower, interval_range, upper) :
  Arguments passed to the following function call: 'scoringutils::interval_score(true_values = 5, lower = 4, upper = 6, interval_range = 95, weigh = TRUE, separate_results = FALSE)' should have the same length (or length one). Arguments have the following lengths:
```

I think the problem is in [check_equal_length()](https://github.com/epiforecasts/scoringutils/blob/cc7bd73748666c9d9faa69fd72c2adf29d7f64b0/R/input-check-helpers.R#L158).

We have
```
vars <- list(true_values = 5,
             lower = 4,
             upper = 6,
             interval_range = 95)
```
and in the check running
```
[HIDDEN]
```
gives `length(unique(lengths)) = 0` so the check fails even though the length of all inputs is equal.

### Additional contract requirements

- When the checked inputs all have length one, validation must accept them as valid and allow the reproduced `interval_score` call to complete.
