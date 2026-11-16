`register_type_strategy` doesn't work with lowercase builtin `list` type
Using `register_type_strategy` doesn't seem to work with the built in `list` type available since python 3.9 (in fact `typing.List` is deprecated).

hypothesis==6.75.1
pytest==7.3.1
Python 3.10.10

```python
from typing import get_args, Type, List
from hypothesis import strategies as st, given, infer


def _shorter_lists(list_type: Type) -> st.SearchStrategy:
    # doesn't get called unless using capital L List
    print("_shorter_lists called")
    sub_type = get_args(list_type)[0]
    return st.lists(st.from_type(sub_type), max_size=2)

# will make our test fail
st.register_type_strategy(list, _shorter_lists)

# will pass if uncommented, notice capital L
# st.register_type_strategy(List, _shorter_lists)


@given(infer)
def test_example(example: list[int]):
    assert len(example) <= 2

```
