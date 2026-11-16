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

The problem is in `HasTraits._sync_trait_items_modified`. When you have a slice like this, the `index` attribute of the trait list event is `None`, causing the logic used to form the slice to fail.

### Additional contract requirements

- For list slice assignments or deletions with step 1 and no explicit start index, the emitted TraitListEvent.index must be 0.
