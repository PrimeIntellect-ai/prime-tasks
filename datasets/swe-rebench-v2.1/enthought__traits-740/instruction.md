items_changed events should not be fired if no items have changed.
After:
```
>>> class A(HasTraits):
...     l = List()
...     def _l_items_changed(self, event):
...         print(f"l changed: index={event.index}, added={event.added}, removed={event.removed}")
```

we see `_l_items_changed` being fired even when the list hasn't changed. For example, see the two lines marked with "Unexpected event!" below.

```
>>> a = A()
>>> a.l
[]
>>> a.l.extend([1, 2, 3])  # get expected event
l changed: index=0, added=[1, 2, 3], removed=[]
>>> a.l.extend([])  # no event, as expected
>>> del a.l[3:]  # Unexpected event!
l changed: index=3, added=[], removed=[]
>>> del a.l[:]  # Expected event
l changed: index=0, added=[], removed=[1, 2, 3]
>>> a.l
[]
>>> del a.l[:]  # Unexpected event!
l changed: index=0, added=[], removed=[]
```
