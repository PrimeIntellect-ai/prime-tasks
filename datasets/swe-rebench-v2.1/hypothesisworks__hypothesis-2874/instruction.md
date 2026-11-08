Can't use registered strategy for typed dict
Here is a reproducible example of the problem:
```python
# test.py
from typing import TypedDict, Callable, NamedTuple

from hypothesis import given
from hypothesis.strategies import composite, register_type_strategy, builds, from_type

class SomeData(TypedDict):
    a: str
    b: int

@composite
def some_data_composite(draw: Callable):
    assert 0  # to be sure when it works

register_type_strategy(SomeData, some_data_composite())

@given(from_type(SomeData))
def test_some_data(item):
    print(item)
```

I'm expecting `pytest test.py` to fail since there is `assert 0` in `some_data_composite` strategy.

The test passes (hypothesis==6.3.0), but if I will replace `class SomeData(TypedDict)` with `class SomeData(NamedTuple)` or `class SomeData`, it will fail.

[HIDDEN]

This seems a problem for me since I'm using Hypothesis with Deal and I want to set up a default strategy for my typed dictionaries.

If this bug is confirmed, I'll try to fix it.

### Additional contract requirements

- When a strategy is registered for a TypedDict using `register_type_strategy`, `from_type` for that TypedDict must use the registered strategy.
