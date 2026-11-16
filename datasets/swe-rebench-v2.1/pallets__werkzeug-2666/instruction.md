`Authorization` should support equality check
As shown in https://github.com/csernazs/pytest-httpserver/issues/241, it can be useful in tests to check if two `Authorization` or `WWWAuthenticate` objects are equal. Implement `__eq__` for both classes.
