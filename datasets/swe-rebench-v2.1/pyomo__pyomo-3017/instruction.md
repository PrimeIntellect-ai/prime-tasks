Pyomo AD fails with constant Expressions
## Summary

Pyomo AD raises an error when encountering `Expressions` with a constant value.

### Steps to reproduce the issue

```console
import pyomo.environ as pyo
from pyomo.core.expr.calculus.derivatives import Modes, differentiate

m = pyo.ConcreteModel()

m.x = pyo.Var(units=pyo.units.mol, initialize=0)

@m.Expression()
def y(blk):
    return 2

@m.Expression()
def product(blk):
    return blk.x * blk.y

diff_expr = differentiate(
                expr=m.product,
                wrt=m.x,
                mode=Modes.reverse_symbolic
            )
diff_expr.pprint()
```

### Error Message

```console
Exception has occurred: KeyError
"Component with id '1907001786672': 2.0"
  File "C:\Users\[REDACTED]\Repos\pyomo\pyomo\common\collections\component_map.py", line 71, in __getitem__
    return self._dict[id(obj)][1]
KeyError: 1907001786672

During handling of the above exception, another exception occurred:

  File "C:\Users\[REDACTED]\Repos\pyomo\pyomo\common\collections\component_map.py", line 73, in __getitem__
    raise KeyError("Component with id '%s': %s" % (id(obj), str(obj)))
  File "C:\Users\[REDACTED]\Repos\pyomo\pyomo\core\expr\calculus\diff_with_pyomo.py", line 331, in _diff_GeneralExpression
    der_dict[node.expr] += der_dict[node]
  File "C:\Users\[REDACTED]\Repos\pyomo\pyomo\core\expr\calculus\diff_with_pyomo.py", line 442, in _reverse_diff_helper
    _diff_GeneralExpression(e, val_dict, der_dict)
  File "C:\Users\[REDACTED]\Repos\pyomo\pyomo\core\expr\calculus\diff_with_pyomo.py", line 484, in reverse_sd
    return _reverse_diff_helper(expr, False)
  File "C:\Users\[REDACTED]\Repos\pyomo\pyomo\core\expr\calculus\derivatives.py", line 96, in differentiate
    res = reverse_sd(expr=expr)
  File "C:\Users\[REDACTED]\Desktop\diff_expr.py", line 16, in <module>
    diff_expr = differentiate(
KeyError: "Component with id '1907001786672': 2.0"
```

### Information on your system
Pyomo version: 6.6.2
Python version: 3.10.10 | packaged by Anaconda, Inc. | (main, Mar 21 2023, 18:39:17) [MSC v.1916 64 bit (AMD64)]
Operating system: Windows 10
How Pyomo was installed (PyPI, conda, source): From sources
Solver (if applicable): n/a
