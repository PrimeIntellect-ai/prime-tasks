Failed assertion when verbosity is `quiet`
Code:

```python
import hypothesis
import hypothesis.strategies

@hypothesis.example(None)
@hypothesis.settings(verbosity=hypothesis.Verbosity.quiet)
@hypothesis.given(hypothesis.strategies.integers())
def f(a):
    pass

f()
```

Failure:

```python
Traceback (most recent call last):
  File "tmp.py", line 10, in <module>
    f()
  File "tmp.py", line 5, in f
    @hypothesis.settings(verbosity=hypothesis.Verbosity.quiet)
  File "/home/gram/.local/lib/python3.8/site-packages/hypothesis/core.py", line 1090, in wrapped_test
    errors = list(
  File "/home/gram/.local/lib/python3.8/site-packages/hypothesis/core.py", line 379, in execute_explicit_examples
    assert fragments_reported[0].startswith("Falsifying example")
IndexError: list index out of range
```

Reason: [HIDDEN]

### Additional contract requirements

- With quiet verbosity, running a test that has an explicit example must not fail with an `IndexError` merely because no report fragment was emitted.
