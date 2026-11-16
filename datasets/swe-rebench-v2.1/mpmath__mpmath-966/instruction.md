Unsupported format string passed to mpf.__format__
```
$ python
Python 3.12.3 (main, Feb  4 2025, 14:48:35) [GCC 13.3.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import mpmath
>>> mpmath.__version__
'1.3.0'
>>> val = mpmath.mpf('0.1')
>>> f"{val:.016f}"
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
TypeError: unsupported format string passed to mpf.__format__
>>>
```
Can you fix this bug?
