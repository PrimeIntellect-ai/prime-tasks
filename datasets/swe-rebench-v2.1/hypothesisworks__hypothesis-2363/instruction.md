Stateful printing referring to undefined variable
Run this example with pytest (hypothesis 5.4.1, but also seen with 4.57.1):
```python
import hypothesis.strategies as st
from hypothesis.stateful import RuleBasedStateMachine, Bundle, initialize, rule


class MyStateMachine(RuleBasedStateMachine):
    data = Bundle('data')

    @initialize(target=data, value=st.integers())
    def init_data(self, value):
        return value

    @rule(d=data)
    def mostly_fails(self, d):
        assert d == 42


Test = MyStateMachine.TestCase
```

It reports this falsifying example:
```
Falsifying example:
state = MyStateMachine()
v1 = state.init_data(value=v1)
state.mostly_fails(d=v1)
state.teardown()
```

But v1 is never initially defined.

### Additional contract requirements

- For this example, the corrected falsifying example must include `v1 = state.init_data(value=0)` and must not include `v1 = state.init_data(value=v1)`.
