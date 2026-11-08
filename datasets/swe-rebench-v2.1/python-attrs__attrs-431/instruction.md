attr.ib cleanup + auto_attribs + class vars from superclasses
Consider the following:

```python
import attr

class Base:
    x = 0

@attr.s(auto_attribs=True)
class C(Base):
    x: int
```

This raises an:

```
Traceback (most recent call last):
  File "t.py", line 9, in <module>
    class C(Base):
  File "/Users/hynek/Projects/attrs/src/attr/_make.py", line 858, in wrap
    return builder.build_class()
  File "/Users/hynek/Projects/attrs/src/attr/_make.py", line 496, in build_class
    return self._patch_original_class()
  File "/Users/hynek/Projects/attrs/src/attr/_make.py", line 514, in _patch_original_class
    delattr(cls, name)
AttributeError: x
```

(interestingly `getattr(cls, name)` works but `delattr` does not)

This is actually quite common if you implement an ABC. [HIDDEN]

[HIDDEN]

### Additional contract requirements

- With `auto_attribs=True`, an annotation-only attribute in a subclass must be usable as an attrs field when a superclass defines a class variable with the same name; no explicit `attr.ib()` should be required.
