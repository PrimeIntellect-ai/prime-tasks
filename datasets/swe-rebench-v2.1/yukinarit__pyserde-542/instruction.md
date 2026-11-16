Flatten does not work with optional dataclass fields
Hi,
Currently trying to move over to using pyserde and dataclasses instead of dictionaries for more type assurance.
I have discovered what I think is a bug for when the `flatten` field attribute is used for fields with optional dataclasses as type.
This example
```python
import serde
from dataclasses import dataclass
from typing import Optional


@serde.serde
@dataclass
class SubStruct:
    sub_id: int
    value: int


@serde.serde
@dataclass
class Struct:
    id: Optional[int]
    sub: Optional[SubStruct] = serde.field(flatten=True)


print(serde.from_dict(Struct, {"id": 123, "sub_id": 69, "value": 420}))
```
I expected this to return `Struct(id=123, sub=SubStruct(sub_id=69, value=420))`.
It does return this if one changes the `sub` field to be `SubStruct` without the Optional.
However with the Optional present (as in the example above) the return is:
`Struct(id=123, sub=None)`

Am I misunderstanding/misusing something?

Thanks
