TypeError: 'decimal.Decimal' object cannot be interpreted as an integer
While trying to improve test coverage, I think I found a bug.

## Environment

```python
$ python -m platform
Linux-5.4.0-107-generic-x86_64-with-glibc2.31

$ python -c "import PyPDF2;print(PyPDF2.__version__)"
1.27.5
```

## Code

This is a minimal, complete example that shows the issue:

```python
>>> from PyPDF2 import xmp
>>> cls = xmp.XmpInformation
>>> cls._converter_date("2021-04-28T12:23:34.123Z")
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/moose/.pyenv/versions/3.10.2/lib/python3.10/site-packages/PyPDF2/xmp.py", line 109, in _converter_date
    dt = datetime.datetime(year, month, day, hour, minute, seconds, milliseconds)
TypeError: 'decimal.Decimal' object cannot be interpreted as an integer

```

## Problem analysis / Fix

The issue seems to be this line:

```
second = decimal.Decimal(m.group("second") or "0")
```

I guess that we can simply convert `seconds` and `milliseconds` to float
