Invariant of a subclass applies to its base
Invariants of subclasses affect their base classes, as well as sibling classes.

Here is a example to reproduce the problem:
```
from icontract import invariant

@invariant(lambda: True)
class Base:
    pass

@invariant(lambda: False)
class Derived(Base):
    pass

Base()  # ViolationError
```

By the way, thanks for the nice library!

### Additional contract requirements

The paragraph and the example above describe the bug reported in the issue. The
required behaviour is that an invariant declared on a subclass must **not** leak to
its base classes or to sibling classes.

Concretely, for the classes in the example above:

- `Base()` must not raise a `ViolationError`.
- Calling a method on an instance of `Base` must not raise a `ViolationError` because
  of the invariant declared on `Derived`.
- `Derived()` must still raise a `ViolationError`, since `Derived` declares the
  invariant `lambda: False`.

More generally, an invariant declared on a class applies to that class and to its own
subclasses, but must not affect any class that is not a subclass of the declaring
class (in particular, not its base classes and not its sibling classes).
