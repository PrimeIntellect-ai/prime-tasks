`set_forecast_unit()` should error if column not found
Currently, `set_forecast_unit()` throws a warning if a column that was specified is not found in the data.
I think this should just be an error. I suggest replacing

```
missing <- check_columns_present(data, forecast_unit)
  if (!is.logical(missing)) {
    [HIDDEN]
  }
```

with

```
[HIDDEN]
```
