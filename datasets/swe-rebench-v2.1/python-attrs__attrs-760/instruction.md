Deferred type annotations are evaluated in the wrong execution context
To reproduce, run the following program:
```python
import attr
from typing import List, get_type_hints

@attr.s
class C:
    x = attr.ib(type='List[int]')

print(get_type_hints(C.__init__))
```

#### Expected result
```
{'return': <class 'NoneType'>, 'x': typing.List[int]}
```

#### Actual result
```
Traceback (most recent call last):
  File "example.py", line 8, in <module>
    print(get_type_hints(C.__init__))
  File "C:\Python37\lib\typing.py", line 1001, in get_type_hints
    value = _eval_type(value, globalns, localns)
  File "C:\Python37\lib\typing.py", line 260, in _eval_type
    return t._evaluate(globalns, localns)
  File "C:\Python37\lib\typing.py", line 464, in _evaluate
    eval(self.__forward_code__, globalns, localns),
  File "<string>", line 1, in <module>
NameError: name 'List' is not defined
```

This annotation should be evaluated in the context of the module where it's defined, where `List` is in globals.

#### Version info
```
attrs 19.3.0
Python 3.7.3 (v3.7.3:ef4ec6ed12, Mar 25 2019, 22:22:05) [MSC v.1916 64 bit (AMD64)] on win32
```
