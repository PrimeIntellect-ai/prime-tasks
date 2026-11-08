Cannot clone individual blocks within an indexed block
## Summary

`_BlockData` does not have a `_parent` attribute, so it cannot be cloned.

<!-- Explain, in a clear and concise way, the command you ran and the result you were trying to achieve.
Example: "I ran `pyomo solve` to optimize a model and ..." -->

### Steps to reproduce the issue

```
In [1]: import pyomo.environ as pe

In [2]: m = pe.ConcreteModel()

In [3]: m.b = pe.Block([1,2,3])

In [4]: m.b[1].clone()
---------------------------------------------------------------------------
AttributeError                            Traceback (most recent call last)
<ipython-input-4-bb20e18a9495> in <module>
----> 1 m.b[1].clone()

~/repos/pyomo/pyomo/core/base/block.py in clone(self)
   1232         # should be preserved as singletons.
   1233         #
-> 1234         save_parent, self._parent = self._parent, None
   1235         try:
   1236             new_block = copy.deepcopy(

~/repos/pyomo/pyomo/core/base/block.py in __getattr__(self, val)
    522         # throw the "normal" AttributeError
    523         raise AttributeError("'%s' object has no attribute '%s'"
--> 524                              % (self.__class__.__name__, val))
    525
    526     def __setattr__(self, name, val):

AttributeError: '_BlockData' object has no attribute '_parent'
```

<!-- Please include the command run and/or provide an example script that demonstrates the problem. -->
