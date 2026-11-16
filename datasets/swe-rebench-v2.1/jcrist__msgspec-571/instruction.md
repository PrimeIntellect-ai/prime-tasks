Bug: `fields` API does not support generic `Structs` if the type is specified
### Description

The `msgspec.structs.fields` API does not support generic types if the type is specified as seen below:

```python
from typing import Generic, TypeVar

from msgspec import Struct
from msgspec.structs import fields

T = TypeVar("T")


class GenericFoo(Struct, Generic[T]):
    foo: T


generic_foo_fields = fields(GenericFoo)  # does not fail
generic_foo_fields = fields(GenericFoo[int])  # fails
```

The reason for this is that `isinstance(GenericFoo[int], type)` will return `False`.
