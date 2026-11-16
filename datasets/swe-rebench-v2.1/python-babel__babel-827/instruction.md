format_timedelta throws a KeyError for the Portuguese locale
## Overview Description

`format_timedelta` throws a KeyError for the Portuguese locale when parsing one hour in short format.

## Steps to Reproduce

```
from datetime import timedelta
from babel.dates import format_timedelta

format_timedelta(timedelta(hours=1), granularity='hour', threshold=100, format='short', locale='pt')
```

## Actual Results
```
Traceback (most recent call last):
  File "/home/user/miniconda3/envs/py38/lib/python3.8/code.py", line 90, in runcode
    exec(code, self.locals)
  File "<input>", line 1, in <module>
  File "/home/user/miniconda3/envs/py38/lib/python3.8/site-packages/babel/dates.py", line 952, in format_timedelta
    pattern = patterns[plural_form]
  File "/home/user/miniconda3/envs/py38/lib/python3.8/site-packages/babel/localedata.py", line 238, in __getitem__
    orig = val = self._data[key]
KeyError: 'one'
```

## Expected Results
```
'1 h'
```

## Additional Information

babel version == 2.9.1
