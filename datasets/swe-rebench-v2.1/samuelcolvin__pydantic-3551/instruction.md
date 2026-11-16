Field with discriminator on generic causes `AssertionError`. (1.9.0a1)

# Bug

When defining a Generic, with a `Field` that has descriminator, filling in the type variable of the generic class fails with an ``AssertionError``.


Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
             pydantic version: 1.9.0a1
            pydantic compiled: True
                 install path: /home/jonathan/.pyenv/versions/3.9.5/envs/lazy-maestro/lib/python3.9/site-packages/pydantic
               python version: 3.9.5 (default, Jun  3 2021, 16:26:08)  [GCC 9.3.0]
                     platform: Linux-5.4.0-91-generic-x86_64-with-glibc2.31
     optional deps. installed: ['dotenv', 'typing-extensions']
```

```py
from typing import Generic, TypeVar, Union

from pydantic import Field
from pydantic.generics import BaseModel, GenericModel
from typing_extensions import Literal

_T = TypeVar("_T")

class Success(GenericModel, Generic[_T]):
    type: Literal["Success"] = "Success"

    data: _T

class Failure(BaseModel):
    type: Literal["Failure"] = "Failure"
    error_message: str

class Container(GenericModel, Generic[_T]):
    result: Union[Success[_T], Failure] = Field(discriminator="type")

# It's the following expresison that raises the traceback below:
Container[str]
```

The error:
```
Traceback (most recent call last):
  File "/tmp/test.py", line 25, in <module>
    Container[str]
  File "/home/jonathan/.pyenv/versions/lazy-maestro/lib/python3.9/site-packages/pydantic/generics.py", line 95, in __class_getitem__
    create_model(
  File "pydantic/main.py", line 959, in pydantic.main.create_model
  File "pydantic/main.py", line 291, in pydantic.main.ModelMetaclass.__new__
  File "pydantic/main.py", line 762, in pydantic.main.BaseModel.__try_update_forward_refs__
  File "pydantic/typing.py", line 477, in pydantic.typing.update_model_forward_refs
    literal (or one of several literals):
  File "pydantic/typing.py", line 456, in pydantic.typing.update_field_forward_refs
    parameters = tuple(_type_check(p, msg) for p in parameters)
  File "pydantic/fields.py", line 735, in pydantic.fields.ModelField.prepare_discriminated_union_sub_fields
AssertionError
```
