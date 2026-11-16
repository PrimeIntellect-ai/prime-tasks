Blank line removal incompatible with black
If a class docstring contains a line that is too long and cannot be reformatted, passing flake8 can be done by appending a `#noqa` to the docstring.
The following was not modified with` docformatter` 1.5.1 and `black` when triggered by `pre-commit`:
```python
class C:
    """Class.""" #noqa

    attr: int
    """Attr."""
```

With `docformatter` 1.6.1, this is changed to:
```python
class C:
    """Class.""" #noqa
    attr: int
    """Attr."""
```

and `pre-commit` always fails because `docformatter` and `black` both apply opposite changes.

This behavior is triggered by the comment appended to the docstring.
