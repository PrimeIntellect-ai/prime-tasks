'quicksum' hides exceptions raised in generator from the user, leading to a wrong model
## Summary
If the generator passed to `quicksum` raises an exception at the first call to __next__, the exception handling logic of `quicksum` will hide the exception from the user and return an expression as `0`.  This behavior of `quicksum` may produce a wrong model unintentionally.

The example below shows that the user misspells `param.aaa` as `param.bbb` in the expression,  in fact it is a non-exsiting attribute of the class. However, the code can run fluently without any exception occurs.

### Steps to reproduce the issue

```python
import pyomo.environ as pyo

class Param:
    def __init__(self) -> None:
        self.aaa = [1.1, 2.2, 3.3]

param = Param()

m = pyo.ConcreteModel()
m.i = pyo.RangeSet(0, 3 - 1)
m.x = pyo.Var(m.i)

m.expr = pyo.Expression(expr=pyo.quicksum(m.x[i] * param.aaa[i] for i in m.i))
m.expr.pprint()

m.expr2 = pyo.Expression(expr=pyo.quicksum(m.x[i] * param.bbb[i] for i in m.i))
m.expr2.pprint()
```
### Error Message
```console
expr : Size=1, Index=None
    Key  : Expression
    None : 1.1*x[0] + 2.2*x[1] + 3.3*x[2]
expr2 : Size=1, Index=None
    Key  : Expression
    None :        0.0
```


### Information on your system

Pyomo version: 6.4.1
Python version: 3.9.12
Operating system: Windows 11
How Pyomo was installed (PyPI, conda, source): conda
