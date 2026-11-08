FBBT fails to compute bounds on NegationExpressions
## Summary

If an expression includes a `NegationExpression`, `compute_bounds_on_expr` returns `(None, None)` in spite of valid bounds existing. (I think this might be related to #846, but I'm not sure, as `NegationExpression` isn't in the list of unsupported expression types?)

### Steps to reproduce the issue

```
from pyomo.environ import *
from pyomo.contrib.fbbt.fbbt import compute_bounds_on_expr
from pyomo.core import summation

m = ConcreteModel()
m.x = Var([0], bounds=(-2,7))

expr_lb, expr_ub = compute_bounds_on_expr(-summation(m.x))
print(expr_lb, expr_ub)
```
Note that `-summation(m.x)` creates a NegationExpression.

### Error Message

The above prints `(None, None)` instead of the expected `(-7, 2)`

### Information on your system

Pyomo version: main branch
Python version: 3.6.5
Operating system: linux
How Pyomo was installed (PyPI, conda, source): source
Solver (if applicable):

### Additional contract requirements

- `pyomo.core.expr.numeric_expr.LinearExpression` is a public class whose constructor is `LinearExpression(constant, linear_coefs, linear_vars)`. It represents the affine expression `constant + sum(linear_coefs[i] * linear_vars[i])`, where `constant` is a numeric scalar or Pyomo expression, `linear_coefs` is a sequence of numeric scalars or Pyomo expressions, and `linear_vars` is a sequence of Pyomo `Var` objects or other numeric expressions with the same length as `linear_coefs`.
- FBBT must support `LinearExpression`: `compute_bounds_on_expr` must compute bounds for an expression that contains a `LinearExpression`, and FBBT must propagate bounds through a constraint whose body is a `LinearExpression`.
