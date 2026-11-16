NL writers linear presolver fails when one variable is left
## Summary
The NL writer's linear presolver will fail if a single variable is left in the model.

### Steps to reproduce the issue

```python
from pyomo.environ import *

m = ConcreteModel()
m.x = Var(bounds=(0, None))
m.y = Var()
m.c = Constraint(expr = m.y == m.x)
m.o = Objective(expr=0)

s = SolverFactory("ipopt_v2")
# s.config.writer_config.linear_presolve = False
s.solve(m)
```

### Error Message

<!-- If Pyomo reported an error, provide the error message. PLEASE INCLUDE THE ENTIRE STACK TRACE. -->

<!-- If it did not report an error but the output appears incorrect, provide the incorrect output. If there was no error message and no output but the result is incorrect, describe how it does not match what you expect. -->
```console
Traceback (most recent call last):
  File "/Users/bknueven/Software/pyomo_test.py", line 11, in <module>
    s.solve(m)
  File "/Users/bknueven/Software/pyomo/pyomo/contrib/solver/base.py", line 522, in solve
    results: Results = super().solve(model)
  File "/Users/bknueven/Software/pyomo/pyomo/contrib/solver/ipopt.py", line 318, in solve
    nl_info = self._writer.write(
  File "/Users/bknueven/Software/pyomo/pyomo/repn/plugins/nl_writer.py", line 409, in write
    return impl.write(model)
  File "/Users/bknueven/Software/pyomo/pyomo/repn/plugins/nl_writer.py", line 1086, in write
    _vmap[_id] = nl.rstrip() % tuple(_vmap[_id] for _id in args)
  File "/Users/bknueven/Software/pyomo/pyomo/repn/plugins/nl_writer.py", line 1086, in <genexpr>
    _vmap[_id] = nl.rstrip() % tuple(_vmap[_id] for _id in args)
KeyError: 140241181484176
```

### Information on your system

Pyomo version: main (f8b02390e3a6e4c14c6486f2c969482f3420ccfb)
Python version: 3.10.9
Operating system: macOS
How Pyomo was installed (PyPI, conda, source): source
Solver (if applicable): N/A


### Additional information

<!-- If you have any additional information, please list it here. -->


<!-- We encourage you to try, as much as possible, to reduce your problem to the minimal example that still reproduces the issue. That would help us a lot in fixing it quickly and effectively!

If you want to ask a question (how to use Pyomo, what it can do, etc.), please refer to our [online documentation](https://github.com/Pyomo/pyomo#getting-help) on ways to get help. -->

Turning off the linear presolver gives the expected result.
