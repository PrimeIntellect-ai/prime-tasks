Mismatch: `OptSolver` versus `set_results_format`
## Summary

[HIDDEN] Not sure if singular/plural is better since I assume it could be both _results_ as well as (a) _result_, but the respective other attribute is called `_results_format `, so I assume `_valid_results_formats` should be the way to go.

### Steps to reproduce the issue

<!-- Please include the command run and/or provide an example script that demonstrates the problem. -->

```python
from pyomo.opt import SolverFactory
from pyomo.opt.base import ProblemFormat

opt = SolverFactory("cbc")
opt.set_results_format(ProblemFormat.cpxlp)
```

### Error Message

```console
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/user/miniconda3/envs/envname/lib/python3.12/site-packages/pyomo/opt/base/solvers.py", line 473, in set_results_format
    if (self._problem_format in self._valid_results_formats) and (
                                ^^^^^^^^^^^^^^^^^^^^^^^^^^^
AttributeError: 'CBCSHELL' object has no attribute '_valid_results_formats'. Did you mean: '_valid_result_formats'?
```

### Information on your system

Pyomo version: 6.7.1
Python version: 3.12.4
Operating system: Ubuntu 20.04
How Pyomo was installed (PyPI, conda, source): mamba
Solver (if applicable): any that supports this (e.g., `gurobi` fails too)


### Additional information

Bug was observed in `v6.7.1` but still persists in latest (b4804976ffc032c9eccc6ac360c857eb1edeb9d2), see:

[HIDDEN]

### Additional contract requirements

- When a solver supports a problem format and a results format for that problem, setting the supported results format must update the selected results format without raising an attribute-related error.
