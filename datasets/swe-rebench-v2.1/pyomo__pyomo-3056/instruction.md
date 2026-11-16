Incorrect degrees of freedom with linear presolve
## Summary

Testing out `NLWriter().write(model, file, linear_presolve=True)`, I have noticed that sometimes a variable that is eliminated is still written to the nl file.

### Steps to reproduce the issue

```python
import pyomo.environ as pyo
import pyomo.repn.plugins.nl_writer as nl_writer
import subprocess

# We use one constraint to eliminate one variable,
# but apparently no variables get eliminated.

m = pyo.ConcreteModel()

m.x = pyo.Var([1, 2, 3], initialize=1, bounds=(0, 10))

m.subexpr = pyo.Expression(pyo.Integers)
m.subexpr[1] = m.x[1] + m.x[2]

m.eq = pyo.Constraint(pyo.Integers)
m.eq[1] = m.x[1] == 7
m.eq[2] = m.x[3] == 0.1 * m.subexpr[1] * m.x[2]

m.obj = pyo.Objective(expr=m.x[1]**2 + m.x[2]**2 + m.x[3]**3)

nl_fname = "test.nl"
with open(nl_fname, "w") as f:
    nlinfo = nl_writer.NLWriter().write(m, f, linear_presolve=True)

print(f"N. var = {len(nlinfo.variables)}")
print(f"N. con = {len(nlinfo.constraints)}")
print(f"N. eliminated = {len(nlinfo.eliminated_vars)}")

print(f"Eliminated: {nlinfo.eliminated_vars[0][0].name}")
print("Variables in nl file:")
for var in nlinfo.variables:
    print(f"  {var.name}")

# Not strictly necessary. This is just here to support the argument that
# the eliminated variable actually makes its way to the nl file.
subprocess.run(["ipopt", nl_fname])
```
This gives:
```console
N. var = 3
N. con = 1
N. eliminated = 1
Eliminated: x[1]
Variables in nl file:
  x[2]
  x[1]
  x[3]
```
Followed by the Ipopt log, which includes:
```console
Total number of variables............................:        3
                     variables with only lower bounds:        0
                variables with lower and upper bounds:        3
                     variables with only upper bounds:        0
Total number of equality constraints.................:        1
Total number of inequality constraints...............:        0
        inequality constraints with only lower bounds:        0
   inequality constraints with lower and upper bounds:        0
        inequality constraints with only upper bounds:        0
```
I would expect the model to have two variables and one constraint after presolve, where instead it (supposedly) has three variables and one constraint.

### Information on your system

Pyomo version: 6.7.0.dev0 (current main)
Python version: 3.9.6
Solver (if applicable): Ipopt 3.14.11 (should not be relevant)

### Hypothesis

[HIDDEN]

I did not understand the substitution code well enough to propose a fix. In particular, it was not clear to me where the substitution is happening. I think I see it for the nonlinear case, but not for the linear case.

### Additional contract requirements

- For the reproduced model, when `linear_presolve=True`, the NL representation has two variables and one constraint; the eliminated variable `m.x[1]` is not included in the NL representation.
- For the reproduced model, `nlinfo.eliminated_vars` equals `[(m.x[1], nl_writer.AMPLRepn(7, {}, None))]`.
