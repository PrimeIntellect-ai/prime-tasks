Multiple Category hierarchies in a single file raise `TraitError`
The following code raises an exception when executed:
```
Traceback (most recent call last):
  File "test2.py", line 15, in <module>
    class E(Category, D):
  File "/Users/mdickinson/Enthought/ETS/traits/traits/category.py", line 75, in __new__
    class_name, bases, class_dict, is_category=True
  File "/Users/mdickinson/Enthought/ETS/traits/traits/has_traits.py", line 709, in update_traits_class_dict
    "definition in a category" % name
traits.trait_errors.TraitError: Cannot override 'trait_added' trait definition in a category
```

Here's the code:
```python
from traits.api import Category, HasTraits, Str

class A(HasTraits):
    a = Str()

class B(Category, A):
    b = Str()

class C(Category, A):
    c = Str()

class D(HasTraits):
    d = Str()

class E(Category, D):
    e = Str()
```

With just `A`, `B` and `C`, or just `D` and `E`, the code executes with no error.

I'd expect the hierarchies `(A, B, C)` and `(D, E)` to be independent of one another.

### Additional contract requirements

- `Category` is importable from `traits.api`. The class attribute `Category.__class_traits__` is a dictionary that remains empty after Category subclasses are defined.
