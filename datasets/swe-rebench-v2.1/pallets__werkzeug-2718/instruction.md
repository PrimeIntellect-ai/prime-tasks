authorization parsing should catch base64 errors
### Steps to reproduce
```
>>> from werkzeug.datastructures import Authorization
>>> Authorization.from_header("Basic foo")
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/private/tmp/.venv/lib/python3.11/site-packages/werkzeug/datastructures/auth.py", line 109, in from_header
    username, _, password = base64.b64decode(rest).decode().partition(":")
                            ^^^^^^^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/python@3.11/3.11.3/Frameworks/Python.framework/Versions/3.11/lib/python3.11/base64.py", line 88, in b64decode
    return binascii.a2b_base64(s, strict_mode=validate)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
binascii.Error: Incorrect padding
```

### Expected behavior
I would expect Werkzeug to handle this situation and return `None`.

### Environment
- Python version: `3.11.3`
- Werkzeug version: `2.3.4`
