Support Functional Inheritance
## Describe the bug

When creating a `class` that inherits from a `DataObjectBase` and overrides parent functions without adding or changing any of the schema, an exception is raised:

```
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
  File "/Users/ghart/Projects/github/caikit/caikit2/caikit/core/data_model/dataobject.py", line 88, in __new__
    raise TypeError(
TypeError: All DataObjectBase classes must follow dataclass syntax
```

## Sample Code

```py
from caikit.core import DataObjectBase, dataobject

@dataobject
class Base(DataObjectBase):
    foo: int
    def doit(self):
        return self.foo * 2

@dataobject
class Derived(Base):
    def doit(self):
        return self.foo * 3
```

## Expected behavior

```py
b_inst = Base(1)
assert b_inst.doit() == 2

d_inst = Derived(1)
assert d_inst.doit() == 3
```

## Observed behavior

```
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
  File "/Users/ghart/Projects/github/caikit/caikit2/caikit/core/data_model/dataobject.py", line 88, in __new__
    raise TypeError(
TypeError: All DataObjectBase classes must follow dataclass syntax
```

## Additional context

This will be very important for allowing content libraries to share common data structures with custom backend, construction, and functional interfaces
