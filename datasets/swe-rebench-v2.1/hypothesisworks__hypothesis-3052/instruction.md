Issues with recursive data classes
Given the following:
```python
from dataclasses import dataclass
from hypothesis import given, strategies as st

@dataclass
class User():
  id: int
  following: list['User']  # works with typing.List

@given(st.builds(User))
def test_user(u):
    pass
```

I always receive the error `hypothesis.errors.InvalidArgument: thing=User must be a type`. I have tried various permutations of using `strategies.recursive` and `strategies.deferred` to define custom strategies and pass them to `@given`, but have been unable to get this to work. I'm not sure if this is a bug or an issue with the documentation (perhaps it requires more recursive examples).

### Additional contract requirements

For the self-referential dataclass example, `st.builds(User)` must either generate a `User` instance or raise `InvalidArgument` with actionable guidance to use a working annotation form. The diagnostic may recommend either using `typing.List["User"]` instead of the builtin `list["User"]`, or using postponed annotations with the self-reference written as `list[User]` (without quotes). The diagnostic must clearly direct users to use its recommended form in place of the unresolved string reference. The recommended form must successfully generate an instance of an equivalent recursive dataclass.
