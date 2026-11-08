Support more format for timezone
# Overview Description

I cannot use `XXXXX` or `ZZZZZ`

# Steps to Reproduce

See this `pycon` log

```pycon
>>> from babel.dates import format_datetime, get_timezone
>>> from datetime import datetime
>>> dt = datetime(2016, 1, 13, 7, 8, 35)
>>> tz = get_timezone('Asia/Seoul')
>>> dt = tz.localize(dt)
>>> format_datetime(dt, 'ZZZZZ')
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/Users/item4/.virtualenvs/lektor/lib/python2.7/site-packages/babel/dates.py", line 618, in format_datetime
    return parse_pattern(format).apply(datetime, locale)
  File "/Users/item4/.virtualenvs/lektor/lib/python2.7/site-packages/babel/dates.py", line 1192, in parse_pattern
    append_field()
  File "/Users/item4/.virtualenvs/lektor/lib/python2.7/site-packages/babel/dates.py", line 1156, in append_field
    % (fieldchar[0] * fieldnum[0]))
ValueError: Invalid length for field: 'ZZZZZ'
>>> format_datetime(dt, 'ZZZ')
u'+0900'
>>> format_datetime(dt, 'XXXXX')
u'XXXXX'
>>> format_datetime(dt, 'XXX')
u'XXX'
```

# Actual Results
`ValueError: Invalid length for field: 'ZZZZZ'` ... etc.

# Expected Results

`ZZZZZ` → `+09:00`
`XXXXX` → `+09:00`

# Reproducibility

100%, Repeat my code.

# Additional Information:

Python 2.7
Mac OS X

See [Date Field Symbol Table](http://unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table) for spec.

### Additional contract requirements

- `format_datetime` must accept the `ZZZZZ` and `XXXXX` timezone patterns on timezone-aware datetimes. For a non-zero UTC offset both produce the offset as sign, hours, colon, minutes (for example `+09:00` for Asia/Seoul, `-08:00` for America/Los_Angeles, `+05:30` for Asia/Kolkata).
- When the UTC offset is zero, both `ZZZZZ` and `XXXXX` produce `Z`.
