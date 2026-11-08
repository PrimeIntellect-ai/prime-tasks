Add Niue holidays
URLs:
- https://en.wikipedia.org/wiki/Public_holidays_in_Niue

### Additional contract requirements

- The `observed_rule` keyword argument must be honored: a caller-supplied rule overrides the default `SAT_SUN_TO_NEXT_MON_TUE` and determines the observed dates. For example, passing `SAT_SUN_TO_NEXT_WED` (from `holidays.observed_holiday_base`) moves a Sunday holiday to the following Wednesday.
- Expose the Niue holiday calendar through the public names `Niue`, `NU`, and `NIU` in `holidays.countries.niue`.
