Shrinker.explain() raises internal assertion
I'm experiencing internal assertion errors from the shrinker. I am using hypothesis 6.130.8 on Linux installed from PYPI.

```
[2025-04-02T17:10:43.319Z]                 # Turns out this was a variable-length part, so grab the infix...
[2025-04-02T17:10:43.319Z]                 if result.status is Status.OVERRUN:
[2025-04-02T17:10:43.319Z]                     continue  # pragma: no cover  # flakily covered
[2025-04-02T17:10:43.319Z]                 result = cast(ConjectureResult, result)
[2025-04-02T17:10:43.319Z]                 if not (
[2025-04-02T17:10:43.319Z]                     len(attempt) == len(result.choices)
[2025-04-02T17:10:43.319Z]                     and endswith(result.nodes, nodes[end:])
[2025-04-02T17:10:43.319Z]                 ):
[2025-04-02T17:10:43.319Z]                     for ex, res in zip(shrink_target.spans, result.spans):
[2025-04-02T17:10:43.319Z]                         assert ex.start == res.start
[2025-04-02T17:10:43.319Z]                         assert ex.start <= start
[2025-04-02T17:10:43.319Z] >                       assert ex.label == res.label
[2025-04-02T17:10:43.319Z] E                       assert 160697414095697247 == 8768992231400091199
[2025-04-02T17:10:43.319Z] E                        +  where 160697414095697247 = spans[4].label
[2025-04-02T17:10:43.319Z] E                        +  and   8768992231400091199 = spans[4].label
[2025-04-02T17:10:43.319Z]
[2025-04-02T17:10:43.319Z] ..python3.11/site-packages/hypothesis/internal/conjecture/shrinker.py:552: AssertionError
```

Any hints about what situations might be causing this would be helpful. So far, I've got a test which always raises an error which results in this assertion instead of an explanation that the problem was irreducible and what the error is that hypothesis is trying to reduce.

```python
import collections

from hypothesis import given
from hypothesis.strategies import (
    one_of,
    none,
    sampled_from,
    fixed_dictionaries,
    composite,
)

MatmulInputs = collections.namedtuple(
    "MatmulInputs",
    [
        "m",
    ],
)


@composite
def matrix_multiply_arrays(draw):
    m = draw(one_of(none(), sampled_from([1])))
    return MatmulInputs(m=m)


options_blocking_values = [True, "auto"]


@given(
    input_arrays=matrix_multiply_arrays(),
    options=one_of(
        none(),
        fixed_dictionaries(
            {
                "blocking": sampled_from(options_blocking_values),
            }
        ),
    ),
)
def test_matmul(input_arrays, options):
    """Call nvmath.linalg.advanced.matmul() with valid inputs."""
    raise RuntimeError("MOCK error that always happens")

```
