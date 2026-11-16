Our internals should handle `StopTest` and other marker exceptions even when wrapped in an `ExceptionGroup`
Hypothesis currently misbehaves if the marker exceptions we raise are wrapped up in an `ExceptionGroup`, e.g.:

```python
import trio
from hypothesis import given, strategies as st

@given(st.data())
def test(data):
    async def task(pred):
        return data.draw(st.booleans().filter(pred))

    @trio.run
    async def _():
        async with trio.open_nursery() as nursery:
            nursery.start_soon(task, bool)
            nursery.start_soon(task, lambda _: False)
```
```
  + Exception Group Traceback (most recent call last):
  |   ...
  +-+---------------- 1 ----------------
    | Traceback (most recent call last):
    |   ...
    | hypothesis.errors.StopTest: 1
    +---------------- 2 ----------------
    | Traceback (most recent call last):
    |   ...
    | hypothesis.errors.Frozen: Cannot call start_example on frozen ConjectureData
    +------------------------------------
```

In such cases I think it's pretty clear that we should treat an exception group _containing_ a `StopTest` as we would a `StopTest` itself.  I think it's also pretty clear that any `Frozen` exceptions inside an `ExceptionGroup` are causally downstream of some other exception, and can therefore be discarded so long as there's any other exception in the group too.

### Additional contract requirements

The marker handling described above applies only when the caught exception
group contains *only* internal marker exceptions — that is, only ``Frozen``,
``StopTest`` and other ``HypothesisException`` subclasses (possibly nested
inside further exception groups). In that case ``Frozen`` markers are
discarded, nested groups are flattened, and the remaining marker is re-raised
as if it had been raised directly:

- a single remaining marker is re-raised unchanged;
- when several ``StopTest`` markers remain, the one with the smallest
  ``testcounter`` is re-raised;
- otherwise the first non-``StopTest`` marker is re-raised.

If the caught group also contains any exception which is *not* one of these
internal markers (for example a user ``TypeError``), the original exception
group is propagated unchanged, preserving all of its members — including any
``Frozen`` and ``StopTest`` entries. In particular, ``Frozen`` is only
discarded when the group contains no non-marker exceptions.
