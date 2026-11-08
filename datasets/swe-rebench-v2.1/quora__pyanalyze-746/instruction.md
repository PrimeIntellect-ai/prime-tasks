pyanalyze doesn't support defining TypeVar under `if TYPE_CHECKING`
```
from typing import TYPE_CHECKING, TypeVar

if TYPE_CHECKING:
    _TypeT = TypeVar("_TypeT", bound=type)

    def c(cls: _TypeT) -> None:
        ...
```
gives:
```
Unrecognized annotation typing.TypeVar (code: invalid_annotation)
In b.py at line 6
   3: if TYPE_CHECKING:
   4:     _TypeT = TypeVar("_TypeT", bound=type)
   5:
   6:     def c(cls: _TypeT) -> None:
                     ^
   7:         ...
```
