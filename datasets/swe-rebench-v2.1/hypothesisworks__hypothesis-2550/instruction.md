Incorrect `TypeVar` + `ForwardRef` resolution
Here's a source code that produces an error:

```python
from hypothesis import strategies as st
from typing import TypeVar

_T = TypeVar('_T', bound='Test')

def example(t: _T) -> None:
    return t.arg

class Test(object):
    def __init__(self, arg: int) -> None:
        self.arg = arg

print(st.builds(example).example())
```

It generates this error:

```
» python ex.py
/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py:268: NonInteractiveExampleWarning: The `.example()` method is good for exploring strategies, but should only be used interactively.  We recommend using `@given` for tests - it performs better, saves and replays failures to avoid flakiness, and reports minimal examples. (strategy: builds(example))
  warnings.warn(
Traceback (most recent call last):
  File "ex.py", line 13, in <module>
    print(st.builds(example).example())
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 314, in example
    example_generating_inner_function()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 302, in example_generating_inner_function
    @settings(
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/core.py", line 1001, in wrapped_test
    processed_args = process_arguments_to_given(
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/core.py", line 420, in process_arguments_to_given
    search_strategy.validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 377, in validate
    self.do_validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/collections.py", line 39, in do_validate
    s.validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 377, in validate
    self.do_validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 638, in do_validate
    self.mapped_strategy.validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 377, in validate
    self.do_validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/lazy.py", line 118, in do_validate
    w.validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 377, in validate
    self.do_validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 638, in do_validate
    self.mapped_strategy.validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 377, in validate
    self.do_validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/collections.py", line 39, in do_validate
    s.validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 377, in validate
    self.do_validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/lazy.py", line 118, in do_validate
    w.validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 377, in validate
    self.do_validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 638, in do_validate
    self.mapped_strategy.validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 377, in validate
    self.do_validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/lazy.py", line 118, in do_validate
    w.validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 377, in validate
    self.do_validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/collections.py", line 39, in do_validate
    s.validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 377, in validate
    self.do_validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 638, in do_validate
    self.mapped_strategy.validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 377, in validate
    self.do_validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/collections.py", line 39, in do_validate
    s.validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 377, in validate
    self.do_validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/lazy.py", line 118, in do_validate
    w.validate()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 378, in validate
    self.is_empty
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 125, in accept
    recur(self)
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/strategies.py", line 121, in recur
    mapping[strat] = getattr(strat, calculation)(recur)
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/deferred.py", line 80, in calc_is_empty
    return recur(self.wrapped_strategy)
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/deferred.py", line 43, in wrapped_strategy
    result = self.__definition()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/core.py", line 1385, in <lambda>
    lambda thing: deferred(lambda: _from_type(thing)),
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/core.py", line 1473, in _from_type
    return types.from_typing_type(thing)
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/types.py", line 152, in from_typing_type
    strat = unwrap_strategies(st.from_type(thing.__bound__))
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/lazy.py", line 45, in unwrap_strategies
    result = unwrap_strategies(s.wrapped_strategy)
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/lazy.py", line 45, in unwrap_strategies
    result = unwrap_strategies(s.wrapped_strategy)
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/deferred.py", line 43, in wrapped_strategy
    result = self.__definition()
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/core.py", line 1385, in <lambda>
    lambda thing: deferred(lambda: _from_type(thing)),
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/core.py", line 1473, in _from_type
    return types.from_typing_type(thing)
  File "/Users/sobolev/Documents/github/returns/.venv/lib/python3.8/site-packages/hypothesis/strategies/_internal/types.py", line 229, in from_typing_type
    raise ResolutionFailed(
hypothesis.errors.ResolutionFailed: Could not resolve ForwardRef('Test') to a strategy; consider using register_type_strategy
```

I guess that this happens due to lack of `ForwardRef` handling here: https://github.com/HypothesisWorks/hypothesis/blob/7d6d048ad5df1d01a4ddc90f1b8f2bb45fe2f0de/hypothesis-python/src/hypothesis/strategies/_internal/types.py#L104

### Additional contract requirements

- Strategy generation for a function annotated with a `TypeVar` whose bound is a forward reference should resolve types available in the module where the `TypeVar` was defined. This includes names introduced through aliases and qualified module attributes. In the reproduction, `st.builds(example).example()` should succeed and return an integer.
- If a referenced type cannot be resolved, an explicitly registered strategy for that `ForwardRef` should remain usable. If neither resolution nor a registered strategy is available, raise `hypothesis.errors.ResolutionFailed`.
