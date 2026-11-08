Output of `pit()` should not be a forecast object
The following fails currently:

```
example_quantile |> pit(by = "model")
```

The reason it fails is that [HIDDEN] and the output of `pit()` in the example is of class `forecast_quantile()`. However, it doesn't have columns `observed` and `predicted`, which means that printing the output fails (we should update the print method to fail gracefully (see #620)).
The output of `pit()` should not be a forecast object. [HIDDEN]

### Additional contract requirements

- `pit()` must return a plain `data.table` (also an S3 `data.frame`) without a forecast-specific class.
