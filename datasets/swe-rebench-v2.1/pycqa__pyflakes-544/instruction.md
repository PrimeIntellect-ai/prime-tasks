F822 (flake8): assigning result of adding tuples with wrong names to `__all__` doesn't warn
This properly warns (`example.py:4:1: F822 undefined name 'Test2' in __all__`):
```py
Test1 = "Test1"

__all__ = ("Test1",)
__all__ += ("Test2",)
```
And this doesn't:
```py
Test1 = "Test1"

__all__ = ("Test1",) + ("Test2",)
```

Version info:
```
$ flake8 --version
3.8.1 (mccabe: 0.6.1, pycodestyle: 2.6.0, pyflakes: 2.2.0) CPython 3.8.2 on Windows
```
