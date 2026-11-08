Incorrect working days calculation in case of substituted holidays from another year
Some countries (e.g. Ukraine, China) have working days moved to the previous or next year (via _substituted holidays_ scheme). If only the year **from which** non-working day is moved is specified, this change is not reflected.

For example, Ukraine has a non-working day moved from December 28, 1996 (Saturday) to January 2, 1997 (Thursday after New Year). Therefore, December 28, 1996 should be a working day. However, it is not:

```python
>>> import holidays
>>> ua = holidays.country_holidays("UA", years=1996)
>>> ua.is_working_day("1996-12-28")
False
```
