Tuple cannot have default_value=None
When creating an `HasTraits` class with a tuple value that can be none, we get an error:

```python
from traitlets import HasTraits, Tuple

class Foo(HasTraits):
    value = Tuple(allow_none=True, default_value=None)
```

Shows:
```
---------------------------------------------------------------------------
TypeError                                 Traceback (most recent call last)
<ipython-input-2-54c571552fdc> in <module>
----> 1 class Foo(HasTraits):
      2     value = Tuple(allow_none=True, default_value=None)
      3

<ipython-input-2-54c571552fdc> in Foo()
      1 class Foo(HasTraits):
----> 2     value = Tuple(allow_none=True, default_value=None)
      3

~/lib/python3.8/site-packages/traitlets/traitlets.py in __init__(self, *traits, **kwargs)
   2414             args = (default_value,)
   2415         else:
-> 2416             raise TypeError('default value of %s was %s' %(self.__class__.__name__, default_value))
   2417
   2418         self._traits = []

TypeError: default value of Tuple was None
```
