Improve handling of self-referential strategies
As mentioned in #2783, the following strategy is not explicitly forbidden but fails with an `AssertionError`:

```python
from hypothesis import strategies as st

SELF_REF = st.recursive(
    st.deferred(lambda: SELF_REF | st.booleans()),
    lambda s: st.lists(s, min_size=1)
)
```

There is an alternative strategy that produces the same data, but doesn't fail the same way:

```python
SELF_REF = st.recursive(
    st.booleans(),
    lambda s: st.lists(s, min_size=1)
)
```

I am not sure if all self-referential strategies can be rewritten like this, but probably we can either explicitly forbid such strategies or revisit our drawing approach for them.

Here is my reasoning from #2783

> As far as I see, the cap is needed to prevent the drawing from this strategy & generating a certain maximum amount of leaves. However, assuming a single thread (more on the multi-threaded behavior in the next section) and such a self-referential strategy, I am not sure if capping is needed as it is - [HIDDEN]

### Additional contract requirements

- The displayed self-referential strategy must either be supported or rejected with a clear user-facing error; it must not fail with an internal `AssertionError`.
