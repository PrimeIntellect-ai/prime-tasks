Sync trait event is broken when setting an empty slice on a list.
Encountering a trait error when setting an empty slice (or a slice without a first index).

Code to reproduce:
```python
from traits.api import *


class Foo(HasStrictTraits):
    data = List(Int)


foo = Foo(data=[-1, -2, -3])
bar = Foo(data=[])
foo.sync_trait('data', bar, mutual=True)
print(foo.data, bar.data)
bar.data[:] = [1, 2, 3]
print(foo.data, bar.data)
```

The problem is in `[HIDDEN]`. When you have a slice like this, [HIDDEN], causing the logic used to form the slice to fail.

### Additional contract requirements

- When a list trait is synchronized between objects, assigning through a slice with no start index must complete without a trait error and leave the synchronized list with the resulting contents.
