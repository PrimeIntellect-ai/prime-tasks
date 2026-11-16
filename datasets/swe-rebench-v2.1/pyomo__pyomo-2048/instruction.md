Set Rewrite Integration TODO's
When integrating the set rewrite with the rest of Pyomo, we need to:

- check the implementation of `IndexedComponent.__iter__`. See the following example for details.
```
>>> import pyomo.environ as pe
>>> from pyomo.core.base.set import Set
>>> m = pe.ConcreteModel()
>>> m.a = Set(initialize=[1,2,3])
>>> list(m.a.values())
[1, 2, 3]
>>> list(m.a.cross(m.a).values())
Traceback (most recent call last):
  File "/Users/mlbynum/Documents/pyomo_big/pyomo_main/pyomo/core/base/set.py", line 902, in _to_0_based_index
    if item != int(item):
TypeError: int() argument must be a string, a bytes-like object or a number, not 'tuple'

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/Users/mlbynum/Documents/pyomo_big/pyomo_main/pyomo/core/base/indexed_component.py", line 356, in itervalues
    yield self[key]
  File "/Users/mlbynum/Documents/pyomo_big/pyomo_main/pyomo/core/base/set.py", line 2780, in __getitem__
    _idx = self._to_0_based_index(index)
  File "/Users/mlbynum/Documents/pyomo_big/pyomo_main/pyomo/core/base/set.py", line 910, in _to_0_based_index
    % (self.name, type(item).__name__,))
IndexError: SetProduct_OrderedSet indices must be integers, not tuple
```

### Additional contract requirements

- `IndexedComponent.values()` yields the component's data objects. For a scalar set, it yields the set object itself.
- `Set.cross(other)` (also spelled with the `*` operator) returns a `SetProduct_OrderedSet` (in `pyomo.core.base.set`). Calling `values()` on the returned product yields a `SetProduct_OrderedSet` object.
- Applying a set operator (`|`, `&`, `-`, `^`, `*`) to an indexed component raises `TypeError` with the message `Cannot apply a Set operator to an indexed <Component> component (<name>)`, where `<Component>` is the component's type name and `<name>` is the component's name.
- Applying a set operator (`|`, `&`, `-`, `^`, `*`) to a component or component data that is not a set raises `TypeError`.
