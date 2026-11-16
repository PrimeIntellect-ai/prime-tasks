`TypeError` on nested `Annotated`s with `typing_extensions==4.12.0`
Minimal repro:

```py
from typing_extensions import Annotated

Annotated[
    list[Annotated[str, {"unhashable_metadata"}]],
    "metadata"
]
```

Traceback:

```pytb
Traceback (most recent call last):
  File "/Users/alexw/dev/repro.py", line 4, in <module>
    Annotated[
  File "/Users/alexw/.pyenv/versions/3.12.3/lib/python3.12/typing.py", line 2090, in __class_getitem__
    return cls._class_getitem_inner(cls, *params)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexw/.pyenv/versions/3.12.3/lib/python3.12/typing.py", line 398, in inner
    return func(*args, **kwds)
           ^^^^^^^^^^^^^^^^^^^
  File "/Users/alexw/.pyenv/versions/3.12.3/lib/python3.12/typing.py", line 2104, in _class_getitem_inner
    return _AnnotatedAlias(origin, metadata)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexw/.pyenv/versions/3.12.3/lib/python3.12/typing.py", line 1997, in __init__
    super().__init__(origin, origin, name='Annotated')
  File "/Users/alexw/.pyenv/versions/3.12.3/lib/python3.12/typing.py", line 1248, in __init__
    self.__parameters__ = _collect_parameters(args)
                          ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexw/dev/pydantic-repro/lib/python3.12/site-packages/typing_extensions.py", line 3028, in _collect_parameters
    [HIDDEN]
                               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  [HIDDEN]
    [HIDDEN]
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexw/.pyenv/versions/3.12.3/lib/python3.12/typing.py", line 2023, in __hash__
    return hash((self.__origin__, self.__metadata__))
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
TypeError: unhashable type: 'set'
```

What makes this particularly bad is that you don't even need to import `Annotated` from `typing_extensions` for this bug to be triggered. It's the monkey-patching we do at import time that causes the problem. This triggers the same traceback:

```py
import typing_extensions
from typing import Annotated

Annotated[
    list[Annotated[str, {"unhashable_metadata"}]],
    "metadata"
]
```

And indeed, you don't even need to import `typing_extensions` directly; if you import anything that in turn imports `typing_extensions`, you'll get that traceback.

This was originally reported as an issue to pydantic: https://github.com/pydantic/pydantic/issues/9503

### Additional contract requirements

- Constructing a nested `typing_extensions.Annotated` type whose inner annotation carries unhashable metadata must succeed and preserve the outer annotation's underlying type and metadata.
- Once `typing_extensions` has been imported, directly constructing the corresponding nested type with `typing.Annotated` must also succeed.
