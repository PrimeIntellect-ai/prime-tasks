Support ClassVar string annotations
The following doesn't work in Python 3.7

```
from __future__ import annotations
import attr
from typing import ClassVar

@attr.dataclass
class A:
    x: ClassVar[int]

a = A()
```

Because `ClassVar[int]` will be `'ClassVar[int]` in `A.__annotations__` and so `[HIDDEN]` returns `False`.

You can repro without 3.7 using this:

```
import attr
from typing import ClassVar

@attr.dataclass
class A:
    x: 'ClassVar[int]'

a = A()
```

Note: It's weird I'm not giving it a value but if I do then attrs will think it's a default value and the code won't error out.

Oh and the following works fine:
```
import attr
import typing

@attr.dataclass
class A:
    x: 'typing.ClassVar[int]'

a = A()
```

### Additional contract requirements

- A string annotation such as `ClassVar[int]` must be recognized as a class variable and excluded from the generated initializer.
