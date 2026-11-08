Invalid handling of zeropad option in mpf formatting
As [docs says](https://docs.python.org/3.14/library/string.html#format-specification-mini-language): "When no explicit alignment is given, preceding the width field by a zero ('0') character enables sign-aware zero-padding for numeric types, excluding [complex](https://docs.python.org/3.14/library/functions.html#complex). This is equivalent to a fill character of '0' with an alignment type of '='."

Example:
```pycon
>>> format(1.1, 'z=13,f')
'zzzzz1.100000'
>>> format(1.1, '=13,f')
'     1.100000'
>>> format(1.1, '0=13,f')
'00,001.100000'
>>> format(1.1, '013,f')
'00,001.100000'
>>> format(mpf(1.1), '0=13,f')
'000001.100000'
>>> format(mpf(1.1), '013,f')
'000001.100000'
```

So, thousands separation is missing.
