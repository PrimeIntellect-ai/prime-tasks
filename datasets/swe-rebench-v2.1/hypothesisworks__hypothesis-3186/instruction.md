stateful _print_step doesn't display invariant
minimal example:
```python
from hypothesis.stateful import *

class StateMachine(RuleBasedStateMachine):
    @invariant()
    def invariant1(self):
        assert False

    @rule()
    def rule1(self):
        assert True

run_state_machine_as_test(StateMachine)
```

Running this code gives:
```
Falsifying example:
state = StateMachine()
state.teardown()
Traceback (most recent call last):
  File "test42.py", line 33, in <module>
    run_state_machine_as_test(StateMachine)
  File "/home/emmanuel/projects/hypothesis-trio/venv/lib/python3.8/site-packages/hypothesis/stateful.py", line 75, in run_state_machine_as_test
    def run_state_machine_as_test(state_machine_factory, *, settings=None):
  File "/home/emmanuel/projects/hypothesis-trio/venv/lib/python3.8/site-packages/hypothesis/internal/reflection.py", line 655, in accept
    return func(*bound.args, **bound.kwargs)
  File "/home/emmanuel/projects/hypothesis-trio/venv/lib/python3.8/site-packages/hypothesis/stateful.py", line 200, in run_state_machine_as_test
    run_state_machine(state_machine_factory)
  File "/home/emmanuel/projects/hypothesis-trio/venv/lib/python3.8/site-packages/hypothesis/stateful.py", line 92, in run_state_machine
    @given(st.data())
  File "/home/emmanuel/projects/hypothesis-trio/venv/lib/python3.8/site-packages/hypothesis/core.py", line 1164, in wrapped_test
    raise the_error_hypothesis_found
  File "test42.py", line 27, in invariant1
    assert False
AssertionError
```

However the falsifying example displayed doesn't trigger the error.
The falsifying should be:
```python
state = StateMachine()
state.invariant1()
state.teardown()
```

### Additional contract requirements

- When a falsifying example is printed, include a line of the form `state.<invariant_name>()` for each invariant evaluation in the trace, including evaluations that return normally, and place each line at its evaluation point in execution order.
