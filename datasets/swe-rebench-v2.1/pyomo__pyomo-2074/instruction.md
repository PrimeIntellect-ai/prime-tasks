`generate_standard_repn` silently fails to capture nonlinear expression
## Summary

In the example below, `generate_standard_repn` fails to record the nonlinear expression at all.

### Steps to reproduce the issue

```
from pyomo.environ import *
from pyomo.repn import generate_standard_repn

m = ConcreteModel()
m.x = Var()
m.y = Var()

expr = (m.x + m.y)*(m.x - m.y)*(m.x**2 + m.y**2)
repn = generate_standard_repn(expr)
print(repn)
```

### Error Message

Output from the script above:
```
constant:       0
linear vars:    []
linear var ids: []
linear coef:    []
quadratic vars:    []
quadratic var ids: []
quadratic coef:    []
nonlinear expr: None
nonlinear vars: []
```

### Information on your system

Pyomo version: main branch
Python version: 3.6.5
Operating system: linux
How Pyomo was installed (PyPI, conda, source): source
Solver (if applicable):

### Additional contract requirements

- For the expression in the reproduction, `str(repn.to_expression())` must equal `(x + y)*(x - y)*(x**2 + y**2)`.
- For `generate_standard_repn(e, compute_values=True)`, the following inputs must produce the exact `str(repn.to_expression())` outputs shown:
- `e = (1 + m.v + m.w + m.v**2)*(m.v + m.w + m.v**2)`: `(1 + v + w + v**2)*(v + w + v**2)`.
- `e = (m.v + m.w + m.v**2)*(1 + m.v + m.w + m.v**2)`: `(v + w + v**2)*(1 + v + w + v**2)`.
- `e = (1 + m.v + m.w + m.v**2)*(1 + m.v + m.w + m.v**2)`: `(1 + v + w + v**2)*(1 + v + w + v**2)`.
