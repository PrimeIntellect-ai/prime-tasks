FBBT of squares written as multiplications
## Summary

This isn't a bug in the sense that it's mathematically wrong, but it seems not ideal: fbbt computes different bounds on m.x*m.x than it does on m.x**2.

### Steps to reproduce the issue

```
from pyomo.environ import *
from pyomo.contrib.fbbt.fbbt import compute_bounds_on_expr

m = ConcreteModel()
m.x = Var([1,2], bounds=(-2,6))

print(compute_bounds_on_expr(m.x[1]*m.x[1] + m.x[2]*m.x[2]))
print(compute_bounds_on_expr(m.x[1]**2 + m.x[2]**2))
```
 outputs
```
(-24, 72)
(0, 72)
```

### Information on your system

Pyomo version: main branch
Python version: 3.6
Operating system: linux
How Pyomo was installed (PyPI, conda, source): source
Solver (if applicable):


### Additional information

<!-- If you have any additional information, please list it here. -->


<!-- We encourage you to try, as much as possible, to reduce your problem to the minimal example that still reproduces the issue. That would help us a lot in fixing it quickly and effectively!

If you want to ask a question (how to use Pyomo, what it can do, etc.), please refer to our [online documentation](https://github.com/Pyomo/pyomo#getting-help) on ways to get help. -->
