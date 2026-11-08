Not throwing error when missing the * to multiply Param and Var
## Summary

When defining a constraint like the following Pyomo will throw an "Invalid constraint expression" Value Error:
```
def const_1(m, t):
    return 0 == m.x(m.y)
m.const_1 = pyo.Constraint(m.t, rule=const_1)
```
In this case I deliberately forgot to place a `*` in order to multiply the values. The function should be:
```
    return 0 == m.x*(m.y)
```

The expected Value Error is:
```console
$ ValueError: Invalid constraint expression. The constraint expression resolved to a trivial Boolean (False) instead of a Pyomo object. Please modify your rule to return Constraint.Infeasible instead of False.

Error thrown for Constraint 'const_1[0]'
```
**However we found that for some specific cases the error won't throw.**

## Error

The following code is ready to run and replicate:
```
import pyomo.environ as pyo
from pyomo.network import *

m = pyo.ConcreteModel()

l_t = [0,1,2,3,4]
m.t = pyo.Set(initialize=l_t)

m.x = pyo.Param(initialize = 0.5, within=pyo.NonNegativeReals)
m.y = pyo.Var(m.t, initialize = [0,0,0,0,0], within=pyo.NonNegativeReals)

def const_1(m, t):
    return m.y[t] == m.x(m.y[t])
m.const_1 = pyo.Constraint(m.t, rule=const_1)

def obj_fun(m):
    return 0
m.goal = pyo.Objective(rule=obj_fun, sense=pyo.minimize)

instance = m.create_instance()
solver = pyo.SolverFactory('ipopt')
solver.solve(instance, tee=True)
```
In this simplified example we define a Param `m.x` and a Var `m.y` which is time dependant (i.e: `m.y[t]`). It is set as a feasibility problem, therefore the objective function returns the value `0`.
**Running the program throws neither warnings nor errors and the solver is able to find an (wrong) optimal solution**

Then we obtained the values for `instance.y` by running:
```
instance.y.get_values()
```

- Missing the `*` :  `{0: 0.5, 1: 0.5, 2: 0.5, 3: 0.5, 4: 0.5}`
- Placing the `*` :  `{0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0}`


### System information

Pyomo version: 6.6.1
Python version: 3.9.13
Operating system: Windows 10
How Pyomo was installed (PyPI, conda, source): pip
Solver (if applicable): ipopt (Ipopt 3.10.1)

### Additional contract requirements

Calling a Param with a non-boolean value for the `exception` argument must raise a `ValueError` instead of silently treating that value as the `exception` flag. This applies both to scalar Params and to individual elements of an indexed Param. The error message must identify the parameter and the offending argument in the form:

`Param '<name>' was called with a non-bool argument for 'exception': <argument>`

For example, calling `m.p(m.p + 2)` on a scalar Param named `p` must raise a `ValueError` containing `Param 'p' was called with a non-bool argument for 'exception': p + 2`, and calling `m.indexed[1](3.2)` on an indexed Param named `indexed` must raise a `ValueError` containing `Param 'indexed[1]' was called with a non-bool argument for 'exception': 3.2`.
