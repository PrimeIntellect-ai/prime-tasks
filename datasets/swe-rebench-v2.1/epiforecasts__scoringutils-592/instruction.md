Create a print method for `forecast_binary`, `forecast_quantile` etc.
The print method should mostly replicate the current behaviour of `check_forecasts()` on the `main` branch. It should call `get_forecast_unit()`, `get_forecast_type()` etc.

### Additional contract requirements

- Support print summaries for `forecast_binary`, `forecast_point`, `forecast_quantile`, and `forecast_sample` objects.
- Include the forecast type and forecast unit in the printed summary, and include score-column names when present.
- Also display the forecast rows in tabular form, as they appear when the forecast object is printed as a data table. These summary fields and rows define the required printed behavior; no other checks or diagnostics from `check_forecasts()` are required.
