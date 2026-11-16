Stack overflows are often reported as flaky.
As mentioned [here](https://stackoverflow.com/a/31770016/3654346), deterministic tests that can hit python's maximum recursion depth may be reported as flaky by Hypothesis, because it is attempted at different initial stack depths.

A simple example that Hypothesis claims is flaky:
```
from hypothesis import given, strategies

def slow(i):
    return 0 if i <= 0 else slow(i - 1) + 1

@given(strategies.integers(min_value=0))
def test_slow(i) -> None:
    assert slow(i) == i

test_slow()
```

Something of a question, rather than a bug report: would we consider detecting RecursionError and giving it some kind of special treatment?

### Additional contract requirements

A deterministic test must not be reported as flaky solely because its available recursion depth differs between Hypothesis attempts, causing one attempt to encounter a `RecursionError`.
