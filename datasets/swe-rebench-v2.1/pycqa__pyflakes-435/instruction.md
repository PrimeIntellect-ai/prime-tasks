F811 (redefinition of unused variable) incorrectly triggered with @overload decorator
This bug was fixed for functions in #320. It still occurs if the function is inside a class and/or has multiple decorators (e.g. @staticmethod, @classmethod):
```python
from typing import overload


class test:
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
test.py:9:5: F811 redefinition of unused 'utf8' from line 5
test.py:13:5: F811 redefinition of unused 'utf8' from line 9
test.py:17:5: F811 redefinition of unused 'utf8' from line 13
```

```python
from typing import overload


def do_nothing(func):
    return func


@overload
@do_nothing
def utf8(value: None) -> None:
    pass


@overload
@do_nothing
def utf8(value: bytes) -> bytes:
    pass


@overload
@do_nothing
def utf8(value: str) -> bytes:
    pass


def utf8(value):
    pass  # actual implementation
```

```
test.py:14:1: F811 redefinition of unused 'utf8' from line 8
test.py:20:1: F811 redefinition of unused 'utf8' from line 14
test.py:26:1: F811 redefinition of unused 'utf8' from line 20
```
