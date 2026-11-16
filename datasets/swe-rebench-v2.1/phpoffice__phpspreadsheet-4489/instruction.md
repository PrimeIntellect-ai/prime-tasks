Regression in 4.3.0: `Date::stringToExcel` requires precision
With the PR #4479, the regex for a valid date/time value was adjusted.
Now it seems to be necessary to specify miliseconds[HIDDEN].

Example:
```php
var_dump(\PhpOffice\PhpSpreadsheet\Shared\Date::stringToExcel("26.05.2025 14:28:00"));
var_dump(\PhpOffice\PhpSpreadsheet\Shared\Date::stringToExcel("26.05.2025 14:28:00.00"));
```

Output 4.2.0:
```
float(45803.60277777778)
bool(false)
```
Output 4.3.0:
```
bool(false)
float(45803.60277777778)
```

I would expect the following:
```
float(45803.60277777778)
float(45803.60277777778)
```

### Additional contract requirements

- `Date::stringToExcel` must accept `26.05.2025 14:28:00` and `26.05.2025 14:28:00.00`, returning the same Excel serial (`45803.60277777778`) for both.
