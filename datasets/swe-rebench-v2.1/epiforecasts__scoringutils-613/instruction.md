[HIDDEN]
Maybe it should also validate in the beginning. --> this would mean it need to be an object of class `forecast_*`.
One alternative would be to just check whether `set_forecast_unit()` introduced a specific error

### Additional contract requirements

- When the input is a forecast object, `set_forecast_unit()` must return a valid forecast object. If more than one row remains for a forecast unit identified by `forecast_unit`, it must raise an error rather than return the invalid result.
