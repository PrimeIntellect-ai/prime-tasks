no example run should mark test as skipped
Currently ( `hypothesis        6.45.1`) when no example is run, the test is marked as success.
One obvious example:
```
from hypothesis import given, settings, example
import hypothesis.strategies as st



@given(my_int=st.integers())
@settings(phases=[])
@example(my_int=51)
def test_integers(my_int):
    assert my_int == 42
```
```
================================================= test session starts ==================================================
platform linux -- Python 3.9.7, pytest-7.1.2, pluggy-1.0.0
rootdir: /home/alexv/tmp/hypofix
plugins: hypothesis-6.45.1
collected 1 item

no_test.py .                                                                                                     [100%]

================================================== 1 passed in 0.11s ===================================================
```

Instead the test should be marked as skipped, as it was never run.

I am not sure how feasible it is, as there are various combinations of `failures_to_reproduce x explicit_examples x phases_configured) that can bring about this behavior.

However when this kind of false positive happens, it is easy to get caught by it, when one is not deeply aware of the details of the test and its configuration...
