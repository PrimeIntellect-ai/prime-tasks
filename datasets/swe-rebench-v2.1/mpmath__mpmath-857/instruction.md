Formatting mpf's is incompatible with Python if formatting type is missing
Documentation [says](https://docs.python.org/3/library/string.html#format-specification-mini-language): "For [float](https://docs.python.org/3/library/functions.html#float) this is the same as 'g', except that when fixed-point notation is used to format the result, it always includes at least one digit past the decimal point. The precision used is as large as needed to represent the given value faithfully."

While we have:
```pycon
>>> f'{mp.mpf(1.23456789):}'  # fixed precision=6
'1.23457'
>>> f'{mp.mpf(1):}'  # no trailing 0
'1'
```

Note, that it might be non-trivial to match exactly Python's output, because e.g. CPython and mpmath use different decimal approximations for some floats.  E.g.:
```pycon
>>> mp.mpf(0.3976135751111121)
mpf('0.39761357511111212')
>>> 0.3976135751111121
0.3976135751111121
>>> 0.39761357511111212
0.3976135751111121
```
