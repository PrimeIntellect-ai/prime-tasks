Fix Plugin.__repr__ to include class name
Currently the `repr` of a `Plugin` subclass is a little misleading with respect to the name of the class:

```python
Python 3.10.10 (main, Feb 10 2023, 08:40:50) [Clang 14.0.0 (clang-1400.0.29.202)] on darwin
Type "help", "copyright", "credits" or "license" for more information.
>>> from envisage.api import CorePlugin
>>> CorePlugin()  # expect a string beginning with 'CorePlugin'
Plugin(id='envisage.core', name='Core')
```

It would be less misleading if the result were `CorePlugin(id='envisage.core', name='Core')`.

This should be an easy fix.

There's an argument that we should refuse the temptation to guess here, since a `Plugin` subclass may have other parameters that should also be mentioned in the `__repr__`. But I think it's still useful to include the plugin class name in the default repr; a subclass can override the `__repr__` if necessary.

xref: the `__repr__` code was relatively recently introduced, in #324. The reviewer apparently failed to pick up this defect at the time.
