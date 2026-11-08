TypeError from inspect.type_info with unhashable Annotated metadata
### Description

## MCVE

```py
from typing import Annotated

import msgspec


class Test(msgspec.Struct):
    a: Annotated[int, {"unhashable": "metadata"}]


t = Test(a=1)

print(t.a)  # 1 (no runtime issues)

msgspec.inspect.type_info(Test)  # TypeError: unhashable type: 'dict'

```

## Error

```
 Traceback (most recent call last):
  File "/home/peter/PycharmProjects/msgspec-mcve/main.py", line 14, in <module>
    msgspec.inspect.type_info(Test)
  File "/home/peter/PycharmProjects/msgspec-mcve/venv/lib/python3.10/site-packages/msgspec/inspect.py", line 614, in type_info
    return multi_type_info([type])[0]
  File "/home/peter/PycharmProjects/msgspec-mcve/venv/lib/python3.10/site-packages/msgspec/inspect.py", line 580, in multi_type_info
    return _Translator(types).run()
  File "/home/peter/PycharmProjects/msgspec-mcve/venv/lib/python3.10/site-packages/msgspec/inspect.py", line 721, in run
    return tuple(self.translate(t) for t in self.types)
  File "/home/peter/PycharmProjects/msgspec-mcve/venv/lib/python3.10/site-packages/msgspec/inspect.py", line 721, in <genexpr>
    return tuple(self.translate(t) for t in self.types)
  File "/home/peter/PycharmProjects/msgspec-mcve/venv/lib/python3.10/site-packages/msgspec/inspect.py", line 755, in translate
    out = self._translate_inner(t, args, **constrs)
  File "/home/peter/PycharmProjects/msgspec-mcve/venv/lib/python3.10/site-packages/msgspec/inspect.py", line 903, in _translate_inner
    type=self.translate(hints[name]),
  File "/home/peter/PycharmProjects/msgspec-mcve/venv/lib/python3.10/site-packages/msgspec/inspect.py", line 724, in translate
    t, args, metadata = _origin_args_metadata(typ)
  [HIDDEN]
TypeError: unhashable type: 'dict'
```

There doesn't seem to be any hard requirement that type metadata via `Annotated` must be hashable (searching for "hash" in [pep 593](https://peps.python.org/pep-0593/) doesn't yield anything), however, the implementation of `_AnnotatedAlias.__hash__()` does hash any metadata as well as the origin type ([ref](https://github.com/python/cpython/blob/1556f426da3f2fb5842689999933c8038b65c034/Lib/typing.py#L1983-L1985)):

```py
    def __hash__(self):
        return hash((self.__origin__, self.__metadata__))
```

### Additional contract requirements

- When `msgspec.inspect.type_info` inspects a type or struct field annotated with `typing.Annotated` carrying unhashable metadata, it must not raise `TypeError` and must return type information for the underlying annotated type.
