Hypothesis's fake Random disagrees with true Random when sampling empty sequences
The following code doesn't work correctly when using Hypothesis's fake random number generator:

```python
from hypothesis import given, strategies as st

@given(rnd=st.randoms(use_true_random=False))
def test_sample_from_empty(rnd):
    assert rnd.sample([], 0) == []
```

It fails with:

```
E           hypothesis.errors.InvalidArgument: Cannot sample from a length-zero sequence.
E           Falsifying example: test_sample_from_empty(
E               rnd=HypothesisRandom(generated data),
E           )
```

But the following test passes:

```
from random import Random

def test_sample_from_empty():
    rnd = Random()
    assert rnd.sample([], 0) == []
```

The issue is that although you can't sample a non-zero number of elements from an empty sequence, it's perfectly valid to sample 0 elements from an empty sequence, and the normal Random class supports this fine but our emulation of it does not.
