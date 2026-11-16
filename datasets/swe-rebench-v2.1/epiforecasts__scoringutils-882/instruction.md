Fix `quantile_score()`
The current `quantile_score()` doesn't work with a single vector as an input. The following line
```
tau_diff <- sweep(obs_smaller_pred, 2, quantile_level)
```

needs to be changed to

```
[HIDDEN]
    tau_diff <- sweep(obs_smaller_pred, 2, quantile_level)
  }
```

--> double check whether that's actually true, i.e. whether we need the ifelse here. Also should there be an absolute value somewhere?

### Additional contract requirements

- `quantile_score(observed, predicted, quantile_level)` computes, for each observation–quantile pair, the quantile score (pinball loss) `2 * (1{observed <= predicted} - quantile_level) * (predicted - observed)`, where `1{...}` is 1 when the condition holds and 0 otherwise. For each observation the returned value is the average of these scores across the supplied quantile levels.
- `predicted` may be supplied either as a numeric matrix with one row per observation and one column per quantile level, or as an atomic numeric vector for a single-row forecast (one element per quantile level). Both forms must return the same scores for the same data.
