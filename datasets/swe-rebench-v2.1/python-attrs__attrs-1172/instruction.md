AttrsInstance is only a Protocol in mypy
`__init__.pyi` defines AttrsInstance as follows:
```
class AttrsInstance(AttrsInstance_, Protocol):
    pass
```

So the following typechecks correctly:
```
import attr
from typing import Protocol

class Foo(attr.AttrsInstance, Protocol):
    def attribute(self) -> int:
        ...


def bar(foo: Foo) -> int:
    return foo.attribute()

@attr.define
class CFoo:
    a: int

    def attribute(self) -> int:
        return self.a

bar(CFoo(15))
```

But if you run it you get:

`TypeError: Protocols can only inherit from other protocols, got <class 'attr.AttrsInstance'>`

Because in `__init__.py` it's defined as:
```
class AttrsInstance:
    pass
```

instead of
```
[HIDDEN]
```
