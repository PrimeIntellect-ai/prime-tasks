Class-level `TypeVar` resulting in "undefined name" error
Minimal sample:
```
from typing import TypeVar


class IdClass:
    Y = TypeVar('Y')

    def id(self, x: Y) -> Y:
        return x
```
Result:
```
# pyflakes t.py
t.py:7: undefined name 'Y'
```

MyPy supports such typing annotations and does not complain about this file.
Probably this issue is related to similar ones #427 and #126
