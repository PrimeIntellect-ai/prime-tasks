Invalid failing example description with `hypothesis.stateful.multiple` containing single value
On my machine with `Python 3.9.5` and `hypothesis==6.37.1` (latest at the moment of writing) test case
```python
from hypothesis.stateful import (Bundle,
                                 RuleBasedStateMachine,
                                 multiple,
                                 rule)


class State(RuleBasedStateMachine):
    values = Bundle('values')

    @rule(target=values)
    def create_single_multiple(self):
        return multiple(42)

    @rule(value=values)
    def check_value(self, value):
        assert value != 42


TestCase = State.TestCase
```
gives
```bash
Falsifying example:
    state = State()
    v1 = state.create_single_multiple()
    state.check_value(value=v1)
    state.teardown()
```
which will succeed because `v1` is `MultipleResults(values=(42,))` but I think it should be `42`, [HIDDEN] so the output will be
```bash
Falsifying example:
    state = State()
    v1, = state.create_single_multiple()
    # ^ note this comma
    state.check_value(value=v1)
    state.teardown()
```

### Additional contract requirements

- When a targeted rule returns exactly one value via `multiple(...)`, the failing-example output must bind that value using singleton unpacking, e.g. `(v1,) = state.populate_bundle()`.
