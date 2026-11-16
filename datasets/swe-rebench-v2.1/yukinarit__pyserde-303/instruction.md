`ClassVar`s don't get serialized?
Example:
```from typing import ClassVar
from serde.se import serialize, to_dict

@serialize
class Foo:
    value: ClassVar[str] = "abc"

print(to_dict(Foo()))  # Prints {}
```

### Additional contract requirements

- ClassVar-annotated attributes are excluded from serialized output by default.
- Set `serialize_class_var=True` on `serde.serialize` or `serde.serde` to enable ClassVar serialization. When enabled, the serialized output includes each annotated attribute using its declared class value.
