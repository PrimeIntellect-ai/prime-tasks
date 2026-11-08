[Bug] Registering a type inheriting from `Sequence`
Hi,
I observe a strange behavior when I create a class that inherits from `Sequence[str]` and registering it with Hypothesis. Namely, the generating strategy for that class is added to one of generating strategies for *general* `Sequence`'s.

Perhaps it is related to https://github.com/HypothesisWorks/hypothesis/issues/2940?

Please have a look:

```python
from typing import Sequence, Union, overload

import hypothesis.strategies as st

class Lines(Sequence[str]):
    """Represent a sequence of text lines."""

    def __new__(cls, lines: Sequence[str]) -> "Lines":
        assert all('\n' not in line and '\r' not in line for line in lines)
        return cast(Lines, lines)

    def __add__(self, other: "Lines") -> "Lines":
        raise NotImplementedError("Only for type annotations")

    # pylint: disable=function-redefined

    @overload
    def __getitem__(self, index: int) -> str:
        pass

    @overload
    def __getitem__(self, index: slice) -> "Lines":
        pass

    def __getitem__(self, index: Union[int, slice]) -> Union[str, "Lines"]:
        raise NotImplementedError("Only for type annotations")

    def __len__(self) -> int:
        raise NotImplementedError("Only for type annotations")

st.register_type_strategy(
    Lines,
    st.fixed_dictionaries(
        {'lines': st.lists(st.text())
            .filter(
            lambda lines:
            all(
                '\n' not in line and '\r' not in line
                for line in lines))
        }
    ).map(lambda d: Lines(**d))
)

strategy = st.from_type(Lines)
assert (str(strategy) ==
        "fixed_dictionaries("
        "{'lines': lists(text())"
        ".filter(lambda lines: <unknown>)})"
        ".map(lambda d: <unknown>)")


# Now let's test that the strategy for ``Sequence[int]`` did not change just because
# we registered a strategy for ``Lines``.
strategy = st.from_type(Sequence[int])

# NOTE: something is strange here.
assert (str(strategy) ==
        "one_of("
        "binary(), "
        "lists(integers()), "
        "fixed_dictionaries("
        "{'lines': lists(text())"
        ".filter(lambda lines: <unknown>)})"
        ".map(lambda d: <unknown>))")
```

### Additional contract requirements

- After registering a strategy for `Lines`, `repr(st.from_type(Sequence[int]))` must be exactly `one_of(binary(), lists(integers()))`.
