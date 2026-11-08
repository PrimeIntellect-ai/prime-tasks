Python 3.10 deprecation in tests due to distutils
The function is simple enough to be vendored for tests.

```
tests/test_converters.py:7
  /root/checked_repos/attrs/tests/test_converters.py:7: DeprecationWarning: The distutils package is deprecated and slated for removal in Python 3.12. Use setuptools or check PEP 632 for potential alternatives
    from distutils.util import strtobool

-- Docs: https://docs.pytest.org/en/stable/warnings.html
```

https://github.com/python-attrs/attrs/blob/d0cff8face92478c950ba05a7d9403b1e342407a/tests/test_converters.py#L7

### Additional contract requirements

Add a public function `to_bool(val)` in the module `attr.converters`.

It converts common textual or numeric boolean representations into actual `bool` values:

- Returns `True` for `True`, `"true"`, `"t"`, `"yes"`, `"y"`, `"on"`, `"1"`, and `1`.
- Returns `False` for `False`, `"false"`, `"f"`, `"no"`, `"n"`, `"off"`, `"0"`, and `0`.
- String values are interpreted case-insensitively.
- Raises `ValueError` with the message `Cannot convert value to bool: <value>` for any other input, including unhashable objects such as lists.

`to_bool` can be composed with other converters, for example via `attr.converters.pipe`.
