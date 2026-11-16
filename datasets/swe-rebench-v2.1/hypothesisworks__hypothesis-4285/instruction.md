st.from_types with Union and Protocol weirdly requires int not to throw
I've managed to extract this MWE from my buggy tests

```python
from typing import ClassVar, Dict, ForwardRef, Protocol, Sequence, TypeAlias, Union

from hypothesis import given, settings
from hypothesis import strategies as st


class IsDataclass(Protocol):
    __dataclass_fields__: ClassVar[Dict]


Extended: TypeAlias = Union[Sequence["Extended"], int, bool, bytes, IsDataclass]

st.register_type_strategy(IsDataclass, st.just(b""))
st.register_type_strategy(
    ForwardRef("Extended"),
    st.recursive(st.one_of(st.integers(), st.booleans(), st.binary()), st.tuples),
)


@given(a=...)
@settings(max_examples=1000)
def test_extended(a: Extended):
    print(a)
```

Defining `Extended` without `int`, ie just like

```
Extended: TypeAlias = Union[Sequence["Extended"], bool, bytes, IsDataclass]
```

will crash with

```
E           TypeError: Instance and class checks can only be used with @runtime_checkable protocols
```

I'm using python3.10 and from my `uv.lock` I see

```
[[package]]
name = "hypothesis"
version = "6.112.1"
source = { registry = "https://pypi.org/simple" }
dependencies = [
    { name = "attrs" },
    { name = "exceptiongroup", marker = "python_full_version < '3.11'" },
    { name = "sortedcontainers" },
]
```
