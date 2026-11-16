`underscore_attrs_are_private` breaks generics
### Checks

* [x] I added a descriptive title to this issue
* [x] I have searched (google, github) for similar issues and couldn't find anything
* [x] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this is a bug

# Bug

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
             pydantic version: 1.7.2
            pydantic compiled: False
                 install path: /nix/store/4snc9a6ywd1m75z7k5v863h9kl3s38dy-python3.7-pydantic-1.7.2/lib/python3.7/site-packages/pydantic
               python version: 3.7.7 (default, Mar 10 2020, 06:34:06)  [GCC 9.3.0]
                     platform: Linux-4.15.0-123-generic-x86_64-with-debian-buster-sid
     optional deps. installed: ['typing-extensions', 'email-validator']

```

----

The `underscore_attrs_are_private` config option seems to break generics. [HIDDEN] Unfortunately, I'm not familiar enough with Pydantic's code to pinpoint the exact root of the issue.

To reproduce:

```py
from pydantic.generics import GenericModel
from typing import TypeVar, Generic

T = TypeVar('T')

class Model(GenericModel, Generic[T]):

	class Config:
		underscore_attrs_are_private = True

	value: T
```

Output:

```python
TypeError                                 Traceback (most recent call last)
<ipython-input-17-86d3af5f0365> in <module>
----> 1 class Model(GenericModel, Generic[T]):
      2     class Config:
      3         underscore_attrs_are_private = True
      4     id: T
      5

/nix/store/5mlyrz5jm75dbjd92wsq89b9lsd0bhww-python3-3.7.7-env/lib/python3.7/site-packages/pydantic/main.py in __new__(mcs, name, bases, namespace, **kwargs)
    322         }
    323
--> 324         cls = super().__new__(mcs, name, bases, new_namespace, **kwargs)
    325         # set __signature__ attr only for model class, but not for its instances
    326         cls.__signature__ = ClassAttribute('__signature__', generate_model_signature(cls.__init__, fields, config))

/nix/store/k2w1idz2vdag50xl88113845mr74z823-python3-3.7.7/lib/python3.7/abc.py in __new__(mcls, name, bases, namespace, **kwargs)
    124         """
    125         def __new__(mcls, name, bases, namespace, **kwargs):
--> 126             cls = super().__new__(mcls, name, bases, namespace, **kwargs)
    127             _abc_init(cls)
    128             return cls

/nix/store/k2w1idz2vdag50xl88113845mr74z823-python3-3.7.7/lib/python3.7/typing.py in __init_subclass__(cls, *args, **kwargs)
    848         tvars = []
    849         if '__orig_bases__' in cls.__dict__:
--> 850             error = Generic in cls.__orig_bases__
    851         else:
    852             error = Generic in cls.__bases__ and cls.__name__ != '_Protocol'

TypeError: argument of type 'member_descriptor' is not iterable

```

----

Removing `underscore_attrs_are_private` or setting it to `False` makes it work as expected. Using `PrivateAttr` instead of the config option works well too.

### Additional contract requirements

- A generic model must be definable and parametrizable when `underscore_attrs_are_private = True`, without raising a `TypeError`.
