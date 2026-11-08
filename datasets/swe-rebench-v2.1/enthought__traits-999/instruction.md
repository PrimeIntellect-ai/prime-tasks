TraitListObject gives bad index for __setitem__
Given the following code:
```
>>> from traits.api import *
>>> class A(HasTraits):
...     foo = List(Int)
...     def _foo_items_changed(self, event):
...         print(f"Index: {event.index}; Added: {event.added}; Removed: {event.removed}")
...
>>> a = A()
>>> a.foo = list(range(10))
>>> a.foo
[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
```

An assignment to `a.foo[5:2]` inserts new items at position `5`. But  the emitted `TraitListEvent` has an index of `2`.

```
>>> a.foo[5:2] = [99]
Index: 2; Added: [99]; Removed: []
>>> a.foo
[0, 1, 2, 3, 4, 99, 5, 6, 7, 8, 9]
```
