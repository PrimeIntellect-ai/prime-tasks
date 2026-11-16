"x in int()" is not flagged as an error
Test case:
```python
def capybara(y: int):
    reveal_type(1 in y)
```

### Additional contract requirements

- A membership test `x in y` where `y` is annotated `int` is reported as an error with code `unsupported_operation`.
- Membership tests are also supported when the type of `y` defines `__getitem__` but not `__contains__`: `x in y` is accepted when the type of `x` is compatible with the parameter type of `__getitem__`, and is reported as `unsupported_operation` when it is not.
