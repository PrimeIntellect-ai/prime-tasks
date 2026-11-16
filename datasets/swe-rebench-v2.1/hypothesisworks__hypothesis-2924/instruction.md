Add helpful error message for `st.sampled_from(EmptyEnumWithAnnotations)`
Following the discussion at #2693, the documented method of sampling from an Enum does not appear to work (or the documentation could use clarification and/or an example). The approach I tried is:

```python
from enum import Enum
from hypothesis import given, strategies as st

class MyEnum(Enum):
    a: 'a'
    b: 'b'

@given(st.sampled_from(MyEnum))
def test_example(instance):
    assert True
```

This raises `hypothesis.errors.InvalidArgument: Cannot sample from a length-zero sequence.` Additionally, `sampled_from(list(MyEnum))` raises the same issue. Hypothesis version is 6.8.5, python is 3.9.2
