The `fmt_date()` function doesn't accept column data of class `Date`
The `fmt_date()` function only works with character-based columns with an ISO formatted date or date-time (the time component is stripped away if detected). It should be possible to accept values of type `Date`. The example in the README gets around this limitation by mutating a date column (with `Date`s) to a `character` column:

```r
sp500 %>%
  dplyr::filter(date >= start_date & date <= end_date) %>%
  dplyr::select(-adj_close) %>%
  dplyr::mutate(date = as.character(date)) %>%
  gt() %>%
  tab_header(
    title = "S&P 500",
    subtitle = glue::glue("{start_date} to {end_date}")
  ) %>%
  fmt_date(
    columns = vars(date),
    date_style = 3
  ) %>%
  fmt_currency(
    columns = vars(open, high, low, close),
    currency = "USD"
  ) %>%
  fmt_number(
    columns = vars(volume),
    scale_by = 1 / 1E9,
    pattern = "{x}B"
  )
```

Basically, this should be made to work without that `mutate()` call.

### Additional contract requirements

- `fmt_date()` must accept columns whose values are of type `Date`, in addition to character-based columns holding ISO 8601 date or date-time strings.
- Values of type `Date` are formatted using the same date styles as the equivalent character-based ISO 8601 date values. For example, `as.Date("2017-10-15")` with `date_style = 3` renders as `Sun, Oct 15, 2017`.
- When a character-based ISO 8601 date-time is formatted with `fmt_date()`, its time component is removed; the result matches formatting the date portion alone.
