assume plus example interacts badly with pytest.mark.parametrize
I can see why I see hypothesis.errors.UnsatisfiedAssumption when I supply an example that fails to satisfy the assumption, though it is inconvenient (I prefer to leave old failures lying around in @example in case I want to remove the assumption later). But it seems like @example is not respecting the parametrized argument it contains? That is, the hypothesis-generated parts are being combined with both parametrize values, and when the example doesn't pass the assumption, I see UnsatisfiedAssumption - even though it is for a combination of values I did not specify.

Sorry, that's not a very clear explanation. But perhaps this contrived example will help:

```python
import pytest
from hypothesis import assume, given, example
from hypothesis.strategies import floats


@given(floats(0, 1))
@example(t=1, f=0.56789)
@pytest.mark.parametrize("t", [0.5, 1])
def test_unsatisfied_assumption(t, f):
    assume(f < t)
    assert f < t
```
yields
```
E           hypothesis.errors.UnsatisfiedAssumption
```
and
```
Falsifying example: test_unsatisfied_assumption(t=0.5, f=0.56789)
```
