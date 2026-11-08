attr.make_class does not work with Python>=3.7
In attr.make_class function [HIDDEN] cannot be used for dynamic generic class creation beyond python 3.7 and leads to an error `TypeError: type() doesn't support MRO entry resolution; [HIDDEN]`.

The error can be recreated with:
```
from typing import TypeVar, Generic
from types import new_class
import attr

MyTypeVar = TypeVar("MyTypeVar")
MyParent = new_class("MyParent", (Generic[MyTypeVar],), {})


attr.make_class('test', {'id': attr.ib(type=str)}, (MyParent[int],))
```

[HIDDEN]

This issue has been discussed here in detail: [https://bugs.python.org/issue33188](https://bugs.python.org/issue33188).

### Additional contract requirements

- On Python 3.7 and later, `attr.make_class` must successfully create a class when given a specialized generic base such as `MyParent[int]` in the reproduction, rather than raising the reported `TypeError`.
