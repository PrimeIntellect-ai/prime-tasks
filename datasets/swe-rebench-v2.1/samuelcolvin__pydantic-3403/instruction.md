Pydantic fail to parse ClassVar annotation when it's a string
### Checks

* [x] I added a descriptive title to this issue
* [x] I have searched (google, github) for similar issues and couldn't find anything
* [x] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this is a bug

<!-- Sorry to sound so draconian, but every second saved replying to issues is time spend improving pydantic :-) -->

# Bug

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
            pydantic version: 1.8.2
            pydantic compiled: False
                 install path: /Users/yuriikarabas/my-projects/pydantic/pydantic
               python version: 3.9.8 (tags/v3.9.8:bb3fdcfe95, Nov 10 2021, 14:54:52)  [Clang 13.0.0 (clang-1300.0.29.3)]
                     platform: macOS-12.0.1-x86_64-i386-64bit
     optional deps. installed: ['devtools', 'dotenv', 'email-validator', 'typing-extensions']
```
<!-- or if you're using pydantic prior to v1.3, manually include: OS, python version and pydantic version -->

<!-- Please read the [docs](https://pydantic-docs.helpmanual.io/) and search through issues to
confirm your bug hasn't already been reported. -->

<!-- Where possible please include a self-contained code snippet describing your bug: -->

```py
from typing import ClassVar

from pydantic import BaseModel


class Model(BaseModel):
    val: "ClassVar[int]" = 10
```
```
Traceback (most recent call last):
  File "/Users/yuriikarabas/my-projects/pydantic/temp.py", line 6, in <module>
    class Model(BaseModel):
  File "/Users/yuriikarabas/my-projects/pydantic/pydantic/main.py", line 187, in __new__
    annotations = resolve_annotations(namespace.get('__annotations__', {}), namespace.get('__module__', None))
  File "/Users/yuriikarabas/my-projects/pydantic/pydantic/typing.py", line 340, in resolve_annotations
    value = _eval_type(value, base_globals, None)
  File "/Users/yuriikarabas/my-projects/cpython/Lib/typing.py", line 292, in _eval_type
    return t._evaluate(globalns, localns, recursive_guard)
  File "/Users/yuriikarabas/my-projects/cpython/Lib/typing.py", line 553, in _evaluate
    type_ = _type_check(
  File "/Users/yuriikarabas/my-projects/cpython/Lib/typing.py", line 158, in _type_check
    raise TypeError(f"{arg} is not valid as type argument")
TypeError: typing.ClassVar[int] is not valid as type argument
```
