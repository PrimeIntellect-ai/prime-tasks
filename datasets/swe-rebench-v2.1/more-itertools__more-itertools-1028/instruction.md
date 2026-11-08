last() fails if __reversed__ is None, which is the case for the Mapping abc
Using `last()` on this class:
```
from collections.abc import Mapping
from more_itertools import last
class MyMapping(Mapping):
    def __getitem__(self, key):
        return 1
    def __iter__(self):
        return iter([1])
    def __len__(self):
        return 1

print(last(iter(MyMapping())))
last(MyMapping())
```

fails with:
```
Traceback (most recent call last):
  File "/nix/store/q3zqcqwmybfda7895g91d75pzbaqj6s5-python3-3.9.20-env/lib/python3.9/site-packages/more_itertools/more.py", line 271, in last
    return next(reversed(iterable))
TypeError: 'MyMapping' object is not reversible

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/home/ibriquem/ws/pyshl/repro.py", line 12, in <module>
    last(MyMapping())
  File "/nix/store/q3zqcqwmybfda7895g91d75pzbaqj6s5-python3-3.9.20-env/lib/python3.9/site-packages/more_itertools/more.py", line 275, in last
    raise ValueError(
ValueError: last() was called on an empty iterable, and no default value was provided.
```

While it works if you first call `iter()` on the object.

This is because `__reversed__` is set to None by the Mapping base class:
https://github.com/python/cpython/blob/4f28afe5456d8ed4a6fe0099337487043e29c912/Lib/_collections_abc.py#L792

I'd expect it to work.

[HIDDEN]

### Additional contract requirements

- `last()` should return the final item of a nonempty iterable even when its `__reversed__` attribute is present and set to `None`.
