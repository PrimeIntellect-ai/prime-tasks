Frozen dataclass behavior change 1.6.1 -> 1.7
### Checks

* [x] I added a descriptive title to this issue
* [x] I have searched (google, github) for similar issues and couldn't find anything
* [x] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this is a bug

<!-- Sorry to sound so draconian, but every second saved replying to issues is time spend improving pydantic :-) -->

# Bug

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
$ python -c "import pydantic.utils; print(pydantic.utils.version_info())"
             pydantic version: 1.7
            pydantic compiled: True
                 install path: /home/user/miniconda3/envs/debug_pydantic/lib/python3.8/site-packages/pydantic
               python version: 3.8.2 (default, May  7 2020, 20:00:49)  [GCC 7.3.0]
                     platform: Linux-5.4.0-52-generic-x86_64-with-glibc2.10
     optional deps. installed: []
```
<!-- or if you're using pydantic prior to v1.3, manually include: OS, python version and pydantic version -->

<!-- Please read the [docs](https://pydantic-docs.helpmanual.io/) and search through issues to
confirm your bug hasn't already been reported. -->

<!-- Where possible please include a self-contained code snippet describing your bug: -->

This code works in v1.6.1:
```py
from dataclasses import dataclass

from pydantic import BaseModel


@dataclass(frozen=True)
class Item:
    name: str


class Example(BaseModel):
    item: Item

    class Config:
        arbitrary_types_allowed = True
```

However, in v1.7, it produces the following error:
```py
Traceback (most recent call last):
  File "/home/user/debug_pydantic.py", line 11, in <module>
    class Example(BaseModel):
  File "pydantic/main.py", line 262, in pydantic.main.ModelMetaclass.__new__
  File "pydantic/fields.py", line 315, in pydantic.fields.ModelField.infer
  File "pydantic/fields.py", line 284, in pydantic.fields.ModelField.__init__
  File "pydantic/fields.py", line 362, in pydantic.fields.ModelField.prepare
  File "pydantic/fields.py", line 538, in pydantic.fields.ModelField.populate_validators
  File "pydantic/validators.py", line 596, in find_validators
  File "pydantic/dataclasses.py", line 222, in make_dataclass_validator
    # and only from the field() function, although Field instances are
  File "pydantic/dataclasses.py", line 214, in pydantic.dataclasses.dataclass
    type_name = self.type.__name__
  File "pydantic/dataclasses.py", line 209, in pydantic.dataclasses.dataclass.wrap
    def __init__(self, type):
  File "pydantic/dataclasses.py", line 126, in pydantic.dataclasses._process_class
    # +=======+=======+=======+========+========+
  File "/home/user/miniconda3/envs/debug_pydantic/lib/python3.8/dataclasses.py", line 1019, in dataclass
    return wrap(cls)
  File "/home/user/miniconda3/envs/debug_pydantic/lib/python3.8/dataclasses.py", line 1011, in wrap
    return _process_class(cls, init, repr, eq, order, unsafe_hash, frozen)
  File "/home/user/miniconda3/envs/debug_pydantic/lib/python3.8/dataclasses.py", line 891, in _process_class
    raise TypeError('cannot inherit non-frozen dataclass from a '
TypeError: cannot inherit non-frozen dataclass from a frozen one
```

Looking through the changelog, this does not appear to be an intentional change. I can remove the `frozen=True` attribute of the dataclass decorator as a workaround, but this seems less than ideal.
