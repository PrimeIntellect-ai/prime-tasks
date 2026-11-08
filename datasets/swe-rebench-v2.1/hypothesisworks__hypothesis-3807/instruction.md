`builds` fails when used with `attrs` classes containing private attributes
Hi, I think I may have found a bug that occurs when using `builds` with automatic attribute inference from `attrs`-built classes that have required but "private" attributes. The bug is probably due to the fact that the name exposed via the constructor differs from the attribute name in these cases, since `attrs` by default strips the leading underscore.

Here a minimal example:

```python
from attrs import define
from hypothesis import given, strategies as st


@define
class MyClass:
    _x: int


@given(st.builds(MyClass))
def test_class(my_obj):
    assert isinstance(my_obj, MyClass)
```

The error you get:

```python
AttributeError: 'MyClassAttributes' object has no attribute 'x'
```
