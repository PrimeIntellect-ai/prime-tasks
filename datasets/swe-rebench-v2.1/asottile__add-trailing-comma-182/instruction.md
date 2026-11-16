`AssertionError: Past end?` on match statement class with no args
Interpreter: Python 3.10

Minimum breaking example:

```python
match 1:
    case str():  # `str()` seems to be important here!
        pass
    case _:
        pass
```

Probably related to #177 .

### Additional contract requirements

Formatting a Python 3.10 or newer `match` statement containing a class pattern with no arguments must complete without raising `AssertionError`.
