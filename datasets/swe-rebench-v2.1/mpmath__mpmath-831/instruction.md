format(mpf(3.14), '') raises ValueError
Reproducer:
```pycon
>>> from mpmath import mpf
>>> format(mpf(3.14), '')
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/sk/src/mpmath/mpmath/ctx_mp_python.py", line 359, in __format__
    return format_mpf(s._mpf_, format_spec)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/sk/src/mpmath/mpmath/libmp/libmpf.py", line 1601, in format_mpf
    format_dict = read_format_spec(format_spec)
                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/sk/src/mpmath/mpmath/libmp/libmpf.py", line 1465, in read_format_spec
    raise ValueError("Invalid format specifier '{}'".format(format_spec))
ValueError: Invalid format specifier ''
```

Instead, this should use default settings, like:
```pycon
>>> format(3.14, '')
'3.14'
```

### Additional contract requirements

- The rounding character `Y` is also supported for `f`, `e`, and `g` formats, and rounds away from zero; for example, `format(mpf('-1.23456789999901234567'), '=.2Yf') == '-1.24'`, `format(mpf('-123.456789999901234567'), '=.2Ye') == '-1.24e+02'`, and `format(mpf('123.456'), '.2Yg') == '1.3e+02'`.
