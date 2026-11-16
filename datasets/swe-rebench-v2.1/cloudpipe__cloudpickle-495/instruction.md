Pickling error for `typing.NamedTuple` on Python 3.9
The current `cloudpickle` `main` branch fails to roundtrip a [`typing.NamedTuple`](https://docs.python.org/3/library/typing.html#typing.NamedTuple) object when run on Python 3.9. Here's an example snippet

```python
import cloudpickle
from typing import NamedTuple

class Record(NamedTuple):
    value: int

result = cloudpickle.dumps(Record(10))
cloudpickle.loads(result)
```

which fails with the following traceback

```python
Traceback (most recent call last):
  File "/Users/james/projects/cloudpipe/cloudpickle/test.py", line 8, in <module>
    cloudpickle.loads(result)
  File "/Users/james/projects/cloudpipe/cloudpickle/cloudpickle/cloudpickle.py", line 823, in _make_skeleton_class
    skeleton_class = types.new_class(
  File "/Users/james/mambaforge/envs/cloudpickle/lib/python3.9/types.py", line 77, in new_class
    return meta(name, resolved_bases, ns, **kwds)
[HIDDEN]
```

Interestingly things seem to work fine on Python 3.7 and 3.8. Additionally, I should note that the above snippet also works on Python 3.9 when using the built-in `pickle` module instead of `cloudpickle`.

This was originally surfaced over in https://github.com/dask/distributed/issues/5602
