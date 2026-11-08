Unusual use of `__new__()` in `NodeWalker`
Hunting for old-style `super()` calls I bumped into the `__new__()` method of the `NodeWalker` class:
```python
class NodeWalker:
    def __new__(cls, *args, **kwargs):
        cls._walker_cache = {}
        return super(NodeWalker, cls).__new__(cls)
```
As the class does not inherit from other classes the use of `super()` seems redundant here as it is equivalent to simply calling `cls()` but this is not what is unusual. What is unusual is modifying the class definition in the `__new__()` method. This means that all `NodeWalker` instances share the same `_walker_cache` dictionary and that this dictionary in reset every time a new `NodeWalker` instance is created. I cannot find a reason why this could be desirable.

[HIDDEN]

### Additional contract requirements

Constructing another walker of the same class must not reset an existing cache and change dispatch decisions already made by that class's walkers.
