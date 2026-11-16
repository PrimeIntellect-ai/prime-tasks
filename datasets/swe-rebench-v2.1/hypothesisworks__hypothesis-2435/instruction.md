Strategy cache thread-safety
Hi!

I encountered a thread-safety issue when multiple threads create strategies. It happens in Schemathesis and the workflow is:
- multiple workers are spawned and consume incoming events
- each event contains data, that is used to create a strategy via `hypothesis_jsonschema.from_schema`

With some probability, a worker thread can fail with an exception like this:

```python-traceback
File /.virtualenvs/schemathesis/lib/python3.8/site-packages/hypothesis/strategies/_internal/core.py", line 172, in cached_strategy
E             STRATEGY_CACHE[cache_key] = result
E           File "/.virtualenvs/schemathesis/lib/python3.8/site-packages/hypothesis/internal/cache.py", line 121, in __setitem__
E             assert evicted.score <= self.data[0].score
E         AssertionError: assert [1, 10062] <= [1, 6901]
```

However, this can be reproduced with this snippet:

```python
import threading
from hypothesis import strategies as st
from functools import partial

def target():
     for _ in range(1000):
         st.builds(partial(str))

for _ in range(4):
     worker = threading.Thread(target=target)
     worker.start()
```

Environment:
- Python 3.8.2
- Hypothesis 5.14.0

And the output is:

```python-traceback
Exception in thread Thread-2:
Traceback (most recent call last):
  File "/usr/lib/python3.8/threading.py", line 932, in _bootstrap_inner
Exception in thread Thread-3:
Traceback (most recent call last):
  File "/usr/lib/python3.8/threading.py", line 932, in _bootstrap_inner
    self.run()
  File "/usr/lib/python3.8/threading.py", line 870, in run
In [8]:     self._target(*self._args, **self._kwargs)
  File "<ipython-input-4-5e40ee0ad813>", line 3, in target
    self.run()
  File "/usr/lib/python3.8/threading.py", line 870, in run
    self._target(*self._args, **self._kwargs)
  File "<ipython-input-4-5e40ee0ad813>", line 3, in target
  File "/.virtualenvs/schemathesis/lib/python3.8/site-packages/hypothesis/strategies/_internal/core.py", line 1177, in builds
  File "/.virtualenvs/schemathesis/lib/python3.8/site-packages/hypothesis/strategies/_internal/core.py", line 1177, in builds
    @defines_strategy
  File "/.virtualenvs/schemathesis/lib/python3.8/site-packages/hypothesis/strategies/_internal/core.py", line 172, in cached_strategy
    STRATEGY_CACHE[cache_key] = result
  File "/.virtualenvs/schemathesis/lib/python3.8/site-packages/hypothesis/internal/cache.py", line 119, in __setitem__
    @defines_strategy
  File "/.virtualenvs/schemathesis/lib/python3.8/site-packages/hypothesis/strategies/_internal/core.py", line 172, in cached_strategy
    assert evicted.score <= self.data[0].score
AssertionError
    STRATEGY_CACHE[cache_key] = result
  File "/.virtualenvs/schemathesis/lib/python3.8/site-packages/hypothesis/internal/cache.py", line 119, in __setitem__
    assert evicted.score <= self.data[0].score
AssertionError
```

As far as I see it is caused by shared storage inside `hypothesis.strategies._internal.core.STRATEGY_CACHE` and access to it is not thread-safe.

[HIDDEN]

I assume that alternative would be using locks either in Hypothesis or on the Schemathesis side, which doesn't seem nice to me.

What do you think about making this cache thread-safe?

### Additional contract requirements

- Concurrent strategy creation must not fail because of races in strategy-cache access.
