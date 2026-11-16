`st.functions(..., pure=True)` very noisy
The generated function output its printed at every invocation, when once per distinct input is sufficient with pure functions. Settings can be used to quiet it down but then a lot of desirable output (including `h.note()`s) is also lost.

minimal example:
```python
import hypothesis as h
import hypothesis.strategies as st

keyfuncs = (
    # choose a return type
    st.sampled_from(
        [
            st.one_of(st.integers(), st.floats(allow_nan=False)),
            st.integers(1, 5).flatmap(
                lambda n: st.tuples(
                    *[st.one_of(st.integers(), st.floats(allow_nan=False))] * n
                )
            ),
        ]
    )
    # get a function with that return type
    .flatmap(lambda strat: st.functions(like=lambda x: x, returns=strat, pure=True))
)


@h.given(f=keyfuncs)
def test_functions_noisy(f):
    h.note(f)
    f(None)
    f(None)
    assert False  # so we get the output
```

output:
```shell
$ pytest hypothesis-functions-noisy.py
=========================================================================================== test session starts ===========================================================================================
platform linux -- Python 3.8.11, pytest-6.2.5, py-1.10.0, pluggy-0.13.1
rootdir: [snip], configfile: pyproject.toml
plugins: anyio-3.3.4, subtests-0.7.0, cov-2.12.1, hypothesis-6.39.3
collected 1 item

hypothesis-functions-noisy.py F

[snip]

----------------------------------------------------------------------------------------------- Hypothesis ------------------------------------------------------------------------------------------------
Falsifying example: test_functions_noisy(
    f=<function hypothesis-functions-noisy.<lambda>.<locals>.<lambda>>,
)
Called function: lambda x: <unknown>(x=None) -> 0
Called function: lambda x: <unknown>(x=None) -> 0
```

### Additional contract requirements

- A generated function created with `pure=True` reports a call no more than once for each distinct input; repeated calls with the same input do not produce additional call reports.
- Calls to a generated function created with `pure=True` using different inputs each produce a call report.
- This reduction in generated-function call reports does not suppress other useful output, including notes made with `h.note()`.
- A generated function created with `pure=False` continues to report every invocation.
