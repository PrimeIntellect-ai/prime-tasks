calculate_variable_from_constraint is unreliable for exponential functions
## Summary

Presently, many models in IDAES rely on the block triangularization provided through `solve_strongly_connected_components`, which relies on `calculate_variable_from_constraint` as solver for 1x1 blocks.  Recently a grad student tried adding a pH property to an existing property package. However, he ran into an `OverflowError` when the solver (presumably) tried to solve the associated block. Theoretically, Newton's method converges for any convex function, but it's possible to overflow before that happens.

If we initialized a constraint of the form `y == 10 ** -x` by hand, it would be trivial to set `x.value = -log10(y)`. Would it be possible to have `calculate_variable_from_constraint` choose from a set of rules for certain simple types of expression instead of immediately falling back on a Newton method? Alternatively, the line search used could cut back the step length if an overflow is detected.

### Steps to reproduce the issue
```
# example.py
import pyomo.environ as pyo
from pyomo.util.calc_var_value import calculate_variable_from_constraint

m = pyo.ConcreteModel()
m.x = pyo.Var(initialize=5)
m.y = pyo.Var(initialize=1)
m.con = pyo.Constraint(expr=m.y == 10 ** (-m.x))

calculate_variable_from_constraint(m.x, m.con)

```

### Error Message

```console
---------------------------------------------------------------------------
OverflowError                             Traceback (most recent call last)
Cell In[1], line 9
      6 m.y = pyo.Var(initialize=1)
      7 m.con = pyo.Constraint(expr=m.y == 10 ** (-m.x))
----> 9 calculate_variable_from_constraint(m.x, m.con)

File ~\miniforge3\envs\idaes-fresh\lib\site-packages\pyomo\util\calc_var_value.py:179, in calculate_variable_from_constraint(variable, constraint, eps, iterlim, linesearch, alpha_min, diff_mode)
    177 if slope:
    178     variable.set_value(-intercept / slope, skip_validation=True)
--> 179     body_val = value(body, exception=False)
    180     if body_val.__class__ not in _invalid_types and abs(body_val - upper) < eps:
    181         # Re-set the variable value to trigger any warnings WRT
    182         # the final variable state
    183         variable.set_value(variable.value)

File ~\miniforge3\envs\idaes-fresh\lib\site-packages\pyomo\common\numeric_types.py:403, in value(obj, exception)
    398         raise
    399 else:
    400     #
    401     # Here, we do not try to catch the exception
    402     #
--> 403     return obj(exception=False)

File ~\miniforge3\envs\idaes-fresh\lib\site-packages\pyomo\core\expr\base.py:118, in ExpressionBase.__call__(self, exception)
    103 def __call__(self, exception=True):
    104     """Evaluate the value of the expression tree.
    105
    106     Parameters
   (...)
    116
    117     """
--> 118     return visitor.evaluate_expression(self, exception)

File ~\miniforge3\envs\idaes-fresh\lib\site-packages\pyomo\core\expr\visitor.py:1314, in evaluate_expression(exp, exception, constant)
   1311         clear_active = True
   1313 try:
-> 1314     ans = visitor.dfs_postorder_stack(exp)
   1315 except (
   1316     TemplateExpressionError,
   1317     ValueError,
   (...)
   1330     #   TypeError: This can be raised in Python3 when evaluating a
   1331     #      operation returns a complex number (e.g., sqrt(-1))
   1332     if exception:

File ~\miniforge3\envs\idaes-fresh\lib\site-packages\pyomo\core\expr\visitor.py:949, in ExpressionValueVisitor.dfs_postorder_stack(self, node)
    945         _result = []
    946 #
    947 # Process the current node
    948 #
--> 949 ans = self.visit(_obj, _result)
    950 if _stack:
    951     #
    952     # "return" the recursion by putting the return value on
    953     # the end of the results stack
    954     #
    955     _stack[-1][-1].append(ans)

File ~\miniforge3\envs\idaes-fresh\lib\site-packages\pyomo\core\expr\visitor.py:1200, in _EvaluationVisitor.visit(self, node, values)
   1198 def visit(self, node, values):
   1199     """Visit nodes that have been expanded"""
-> 1200     return node._apply_operation(values)

File pyomo\\core\\expr\\numeric_expr.pyx:952, in pyomo.core.expr.numeric_expr.PowExpression._apply_operation()

OverflowError: (34, 'Result too large')
```

### Information on your system

Pyomo version: 6.9.0
Python version: 3.10.15
Operating system: Windows 10
How Pyomo was installed (PyPI, conda, source): Probably pip?
Solver (if applicable): n/a
