F811 (redefinition of unused variable) incorrectly triggered with @overload decorator
PEP 484 [introduced](https://www.python.org/dev/peps/pep-0484/#function-method-overloading) the `@overload` decorator for type annotations.

> [...] a series of `@overload`-decorated definitions must be followed by exactly one non-@overload-decorated definition (for the same function/method). The `@overload`-decorated definitions are for the benefit of the type checker only, since they will be overwritten by the non-`@overload`-decorated definition, while the latter is used at runtime but should be ignored by a type checker.

The following should pass PyFlakes without errors, but currently triggers F811 errors:

```python
from typing import overload


@overload
def utf8(value: None) -> None:
    pass


@overload
def utf8(value: bytes) -> bytes:
    pass


@overload
def utf8(value: str) -> bytes:
    pass


def utf8(value):
    pass  # actual implementation
```
```
test.py:9:1: F811 redefinition of unused 'utf8' from line 4
test.py:14:1: F811 redefinition of unused 'utf8' from line 9
test.py:19:1: F811 redefinition of unused 'utf8' from line 14
```

### Additional contract requirements

- The exemption applies to module-level functions and to methods defined in a class body.
- The decorator is recognized both when imported directly (`from typing import overload`; `@overload`) and when accessed through the `typing` module (`import typing`; `@typing.overload`).
