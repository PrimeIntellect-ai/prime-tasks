runtime_checkable error in newer versions caused by a protocol subclass
Consider the following code:
```python
from typing import Sized

isinstance(1, Sized)
```
This works well and returns `False`, as expected.

However, if I create a new protocol that subclass `Sized`:
```python
from typing_extensions import Protocol

class MySized(Protocol, Sized):
    pass

isinstance(1, Sized)
```
This now raises the following exception:

<details>

```python
TypeError                                 Traceback (most recent call last)
<ipython-input-5-2516c5c4af5f> in <module>
----> 1 isinstance(1, Sized)

.../lib/python3.8/typing.py in __instancecheck__(self, obj)
    764
    765     def __instancecheck__(self, obj):
--> 766         return self.__subclasscheck__(type(obj))
    767
    768     def __subclasscheck__(self, cls):

.../lib/python3.8/typing.py in __subclasscheck__(self, cls)
    769         if self._special:
    770             if not isinstance(cls, _GenericAlias):
--> 771                 return issubclass(cls, self.__origin__)
    772             if cls._special:
    773                 return issubclass(cls.__origin__, self.__origin__)

.../lib/python3.8/abc.py in __subclasscheck__(cls, subclass)
    100         def __subclasscheck__(cls, subclass):
    101             """Override for issubclass(subclass, cls)."""
--> 102             return _abc_subclasscheck(cls, subclass)
    103
    104         def _dump_registry(cls, file=None):

.../lib/python3.8/site-packages/typing_extensions.py in __subclasscheck__(cls, other)
    581                     "Protocols with non-method members don't support issubclass()"
    582                 )
--> 583             return super().__subclasscheck__(other)
    584
    585         def __instancecheck__(cls, instance):

.../lib/python3.8/abc.py in __subclasscheck__(cls, subclass)
    100         def __subclasscheck__(cls, subclass):
    101             """Override for issubclass(subclass, cls)."""
--> 102             return _abc_subclasscheck(cls, subclass)
    103
    104         def _dump_registry(cls, file=None):

.../lib/python3.8/site-packages/typing_extensions.py in _proto_hook(cls, other)
    637             if _allow_reckless_class_checks():
    638                 return NotImplemented
--> 639             raise TypeError("Instance and class checks can only be used with"
    640                             " @runtime_checkable protocols")
    641

TypeError: Instance and class checks can only be used with @runtime_checkable protocols
```

</details>

This non-local behavior did not happen in prior versions, and has caused problems in my code (https://github.com/GAA-UAM/scikit-fda/issues/540).
