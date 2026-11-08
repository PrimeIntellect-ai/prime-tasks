Inconsistent handling of newlines in Headers object
Werkzeug's `Headers` object is inconsistent in its handling of newline characters.  These characters are allowed in the constructor but forbidden in the `add()` method.

**Steps to reproduce:**
```
>>> from werkzeug import Headers
>>> h1 = Headers([('X-Example', 'foo\r\n bar')])
>>> h2 = Headers()
>>> h2.add('X-Example', 'foo\r\n bar')
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/.../venv3/lib/python3.6/site-packages/werkzeug/datastructures.py", line 1166, in add
    self._validate_value(_value)
  File "/home/.../venv3/lib/python3.6/site-packages/werkzeug/datastructures.py", line 1173, in _validate_value
    raise ValueError('Detected newline in header value.  This is '
ValueError: Detected newline in header value.  This is a potential security problem
```

**Expected result:**
Both operations have the same result, whether a `ValueError` or success.

**Actual result:**
`Headers` constructor allows newlines while `Headers.add()` raises `ValueError`.
