`st.builds()` works incorrectly with annotated `__init__`
The simplest reproduction is:

```python
from typing import Generic, TypeVar

from hypothesis import given
from hypothesis import strategies as st

_ValueType = TypeVar('_ValueType')


class Wrapper(Generic[_ValueType]):
    _inner_value: _ValueType

    def __init__(self, inner_value: _ValueType) -> None:
        self._inner_value = inner_value


@given(st.builds(Wrapper))
def test_wrapper(wrapper):
    assert isinstance(wrapper, Wrapper)

```

Outputs:

```
====================================== FAILURES ======================================
____________________________________ test_wrapper ____________________________________

    @given(st.builds(Wrapper))
>   def test_wrapper(wrapper):

ex2.py:24:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
.venv/lib/python3.7/site-packages/hypothesis/core.py:684: in _execute_once_for_engine
    escalate_hypothesis_internal_error()
.venv/lib/python3.7/site-packages/hypothesis/core.py:655: in _execute_once_for_engine
    result = self.execute_once(data)
.venv/lib/python3.7/site-packages/hypothesis/core.py:610: in execute_once
    result = self.test_runner(data, run)
.venv/lib/python3.7/site-packages/hypothesis/executors.py:52: in default_new_style_executor
    return function(data)
.venv/lib/python3.7/site-packages/hypothesis/core.py:550: in run
    args, kwargs = data.draw(self.search_strategy)
.venv/lib/python3.7/site-packages/hypothesis/internal/conjecture/data.py:889: in draw
    return strategy.do_draw(self)
.venv/lib/python3.7/site-packages/hypothesis/strategies/_internal/collections.py:57: in do_draw
    return tuple(data.draw(e) for e in self.element_strategies)
.venv/lib/python3.7/site-packages/hypothesis/strategies/_internal/collections.py:57: in <genexpr>
    return tuple(data.draw(e) for e in self.element_strategies)
.venv/lib/python3.7/site-packages/hypothesis/internal/conjecture/data.py:884: in draw
    return strategy.do_draw(self)
.venv/lib/python3.7/site-packages/hypothesis/strategies/_internal/strategies.py:650: in do_draw
    result = self.pack(data.draw(self.mapped_strategy))
.venv/lib/python3.7/site-packages/hypothesis/internal/conjecture/data.py:884: in draw
    return strategy.do_draw(self)
.venv/lib/python3.7/site-packages/hypothesis/strategies/_internal/lazy.py:150: in do_draw
    return data.draw(self.wrapped_strategy)
.venv/lib/python3.7/site-packages/hypothesis/internal/conjecture/data.py:884: in draw
    return strategy.do_draw(self)
.venv/lib/python3.7/site-packages/hypothesis/strategies/_internal/strategies.py:650: in do_draw
    result = self.pack(data.draw(self.mapped_strategy))
.venv/lib/python3.7/site-packages/hypothesis/internal/conjecture/data.py:884: in draw
    return strategy.do_draw(self)
.venv/lib/python3.7/site-packages/hypothesis/strategies/_internal/collections.py:57: in do_draw
    return tuple(data.draw(e) for e in self.element_strategies)
.venv/lib/python3.7/site-packages/hypothesis/strategies/_internal/collections.py:57: in <genexpr>
    return tuple(data.draw(e) for e in self.element_strategies)
.venv/lib/python3.7/site-packages/hypothesis/internal/conjecture/data.py:884: in draw
    return strategy.do_draw(self)
.venv/lib/python3.7/site-packages/hypothesis/strategies/_internal/lazy.py:150: in do_draw
    return data.draw(self.wrapped_strategy)
.venv/lib/python3.7/site-packages/hypothesis/internal/conjecture/data.py:884: in draw
    return strategy.do_draw(self)
.venv/lib/python3.7/site-packages/hypothesis/strategies/_internal/strategies.py:650: in do_draw
    result = self.pack(data.draw(self.mapped_strategy))
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

value = ((), {})

>       lambda value: target(*value[0], **value[1])  # type: ignore
    )
E   TypeError: __init__() missing 1 required positional argument: 'inner_value'

.venv/lib/python3.7/site-packages/hypothesis/strategies/_internal/core.py:1313: TypeError
```

Why does this happen?

My debugging session shows that:
- `required` [here](https://github.com/HypothesisWorks/hypothesis/blob/d1efdd688d889931427afa0defdc4abdbfc95c1a/hypothesis-python/src/hypothesis/strategies/_internal/core.py#L1282) is equal to `{'inner_value'}`
- [HIDDEN]
- And since these two sets do not match, the [resulting set here](https://github.com/HypothesisWorks/hypothesis/blob/d1efdd688d889931427afa0defdc4abdbfc95c1a/hypothesis-python/src/hypothesis/strategies/_internal/core.py#L1297) is empty
- And that's why we have this error 😢

I can fix it! The only question I have is:
[HIDDEN]

### Additional contract requirements

- `st.builds()` should successfully construct an instance of a class when its required `__init__` argument is annotated, rather than failing because the argument is missing.
