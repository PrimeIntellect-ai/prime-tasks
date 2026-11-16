Bug in pyomo/repn/linear.py
## Summary

Solve a quadratic program (or QCQP) using cplex/gurobi with exponents that are written using floats, rather than integers

### Steps to reproduce the issue

Use `m.x1**2.0` instead of `m.x1**2`


<!-- Please include the command run and/or provide an example script that demonstrates the problem. -->

```console
$ python example.py
```

```
# example.py
from pyomo.environ import *

model = m = ConcreteModel()

m.x1 = Var(within=Reals, bounds=(0,10), initialize=0)

m.obj = Objective(sense=minimize, expr= (m.x1**2.0 + m.x1 - 2))

opt = SolverFactory('cplex')
opt.solve(m, tee=True)
```

### Error Message

<!-- If Pyomo reported an error, provide the error message. PLEASE INCLUDE THE ENTIRE STACK TRACE. -->

<!-- If it did not report an error but the output appears incorrect, provide the incorrect output. If there was no error message and no output but the result is incorrect, describe how it does not match what you expect. -->
```console
$ # Output message here, including entire stack trace, if available
Traceback (most recent call last):
  File "/home/will/Documents/research-minlp/mindtpy/pyomo/Lin_repn_bug/ex1223_solve_linear.py", line 28, in <module>
    opt.solve(m, tee=True)
  File "/home/will/anaconda3/envs/pyomoMinlp/lib/python3.9/site-packages/pyomo/opt/base/solvers.py", line 597, in solve
    self._presolve(*args, **kwds)
  File "/home/will/anaconda3/envs/pyomoMinlp/lib/python3.9/site-packages/pyomo/solvers/plugins/solvers/CPLEX.py", line 354, in _presolve
    ILMLicensedSystemCallSolver._presolve(self, *args, **kwds)
  File "/home/will/anaconda3/envs/pyomoMinlp/lib/python3.9/site-packages/pyomo/opt/solver/shellcmd.py", line 224, in _presolve
    OptSolver._presolve(self, *args, **kwds)
  File "/home/will/anaconda3/envs/pyomoMinlp/lib/python3.9/site-packages/pyomo/opt/base/solvers.py", line 706, in _presolve
    ) = self._convert_problem(
  File "/home/will/anaconda3/envs/pyomoMinlp/lib/python3.9/site-packages/pyomo/opt/base/solvers.py", line 757, in _convert_problem
    return convert_problem(
  File "/home/will/anaconda3/envs/pyomoMinlp/lib/python3.9/site-packages/pyomo/opt/base/convert.py", line 99, in convert_problem
    problem_files, symbol_map = converter.apply(*tmp, **tmpkw)
  File "/home/will/anaconda3/envs/pyomoMinlp/lib/python3.9/site-packages/pyomo/solvers/plugins/converter/model.py", line 78, in apply
    (problem_filename, symbol_map_id) = instance.write(
  File "/home/will/anaconda3/envs/pyomoMinlp/lib/python3.9/site-packages/pyomo/core/base/block.py", line 1983, in write
    (filename, smap) = problem_writer(self, filename, solver_capability, io_options)
  File "/home/will/anaconda3/envs/pyomoMinlp/lib/python3.9/site-packages/pyomo/repn/plugins/lp_writer.py", line 207, in __call__
    info = self.write(model, FILE, **io_options)
  File "/home/will/anaconda3/envs/pyomoMinlp/lib/python3.9/site-packages/pyomo/repn/plugins/lp_writer.py", line 240, in write
    return _LPWriter_impl(ostream, config).write(model)
  File "/home/will/anaconda3/envs/pyomoMinlp/lib/python3.9/site-packages/pyomo/repn/plugins/lp_writer.py", line 350, in write
    repn = objective_visitor.walk_expression(obj.expr)
  File "/home/will/anaconda3/envs/pyomoMinlp/lib/python3.9/site-packages/pyomo/core/expr/visitor.py", line 269, in walk_expression
    result = self._process_node(root, RECURSION_LIMIT)
  File "/home/will/anaconda3/envs/pyomoMinlp/lib/python3.9/site-packages/pyomo/core/expr/visitor.py", line 422, in _process_node_bex
    data.append(self._process_node(child, recursion_limit))
  File "/home/will/anaconda3/envs/pyomoMinlp/lib/python3.9/site-packages/pyomo/core/expr/visitor.py", line 435, in _process_node_bex
    return self.exitNode(node, data)
  File "/home/will/anaconda3/envs/pyomoMinlp/lib/python3.9/site-packages/pyomo/repn/linear.py", line 893, in exitNode
    return self.exit_node_dispatcher[(node.__class__, *map(itemgetter(0), data))](
  [HIDDEN]
TypeError: 'float' object cannot be interpreted as an integer
```

### Information on your system

Pyomo version: 6.6.1
Python version: 3.9
Operating system: Ubuntu 22.04
How Pyomo was installed (PyPI, conda, source): conda
Solver (if applicable): cplex, also noticed the same issue with gurobi. Ipopt and baron had no issues


### Additional information

<!-- If you have any additional information, please list it here. -->
[HIDDEN]

<!-- We encourage you to try, as much as possible, to reduce your problem to the minimal example that still reproduces the issue. That would help us a lot in fixing it quickly and effectively!

If you want to ask a question (how to use Pyomo, what it can do, etc.), please refer to our [online documentation](https://github.com/Pyomo/pyomo#getting-help) on ways to get help. -->

### Additional contract requirements

- A quadratic expression raised to `2.0` must be handled equivalently to the same expression raised to `2`, and must be exportable to CPLEX or Gurobi without a `TypeError`.
