contrib.deactivate_trivial_constraints can miss trivial constraints
## Summary

The `contrib.deactivate_trivial_constraints` transformation uses the polynomial degree of the constraint expression to decide if the expression is constant. That's not actually a reliable method of doing so, meaning that it can miss trivial constraints like in the example below, where the polynomial degree of the constraint body evaluates to 1.

### Steps to reproduce the issue

```
from pyomo.environ import *

m = ConcreteModel()
m.x = Var()
m.y = Var()
m.y.fix(0)
m.c = Constraint(expr=m.x*m.y >= 0)

TransformationFactory('contrib.deactivate_trivial_constraints').apply_to(m)

print(m.c.active) # True
```

### Information on your system

Pyomo version: main
Python version: 3.8
Operating system: linux
How Pyomo was installed (PyPI, conda, source): source
Solver (if applicable):


### Additional information

[HIDDEN] This isn't a bug in the sense that it does the wrong thing, but it does fall short on its promises.

### Additional contract requirements

- The transformation must deactivate feasible constraints whose bodies are constant, including when polynomial degree does not identify the body as constant.
