Indexed SOS1 constraints raise errors with SCIP and pyomo 6.5.0
## Summary

I updated pyomo to the latest version (6.5.0) and now I cannot solve AbstractModel problems with indexed SOS1 constraints using SCIP. I could using a previous version of pyomo (6.4.2).

Instead, I get the following AttributeError: 'IndexedSOSConstraint' object has no attribute 'variables'

The error is not raised if I use CPLEX (22.1.1.0). Also, the problem does not appear to be due to SCIP, since it can recognise the constraints and solve the problem via the command line. I can also use non-indexed SOS1 constraints with either solver.

### Steps to reproduce the issue

The error can be reproduced using the code below:

```
# abstract model

import pyomo.environ as pyo

model = pyo.AbstractModel()
model.A = pyo.Set(initialize=[1])
model.B = pyo.Set(initialize=[1,2,3])
model.C = pyo.Set(initialize=[1])

model.param_cx = pyo.Param(model.A, initialize={1:1})
model.param_cy = pyo.Param(model.B, initialize={1:2, 2:3, 3:1})

model.x = pyo.Var(model.A, domain=pyo.NonNegativeReals, bounds=(0,40))
model.y = pyo.Var(model.B, domain=pyo.NonNegativeIntegers)

def obj_f(m):
    return (
        sum(m.param_cx[a]*m.x[a] for a in m.A)
        +
        sum(m.param_cy[b]*m.y[b] for b in m.B)
        )

model.OBJ = pyo.Objective(
    rule=obj_f
    )

def constr_y3_lb(m):
    return m.y[3] >= 2
def constr_y3_ub(m):
    return m.y[3] <= 3

model.ConstraintY3_lb = pyo.Constraint(rule=constr_y3_lb)
model.ConstraintY3_ub = pyo.Constraint(rule=constr_y3_ub)

# does not work: 'IndexedSOSConstraint' object has no attribute 'variables'

model.mysos = pyo.SOSConstraint(model.C,
                                var=model.y,
                                sos=1,
                                index={1:[2,3]}
                                )

# # does not work either: 'IndexedSOSConstraint' object has no attribute 'variables'

# model.mysos = pyo.SOSConstraint(model.C,
#                                 var=model.y,
#                                 sos=1,
#                                 index={1:[2,3]},
#                                 weights={2: 25.0, 3: 18.0},
#                                 )

inst = model.create_instance()

opt = pyo.SolverFactory('scip') # must be sos-compatible solver
opt.solve(inst,tee=True)
```

### Error Message

The error takes place in the nl_writer.py file, which has recently undergone some changes.

```console
Traceback (most recent call last):

  Cell In[100], line 56
    opt.solve(inst,tee=True)

  File ~/myvenv/lib/python3.11/site-packages/pyomo/opt/base/solvers.py:570 in solve
    self._presolve(*args, **kwds)

  File ~/myvenv/lib/python3.11/site-packages/pyomo/opt/solver/shellcmd.py:219 in _presolve
    OptSolver._presolve(self, *args, **kwds)

  File ~/myvenv/lib/python3.11/site-packages/pyomo/opt/base/solvers.py:667 in _presolve
    self._convert_problem(args,

  File ~/myvenv/lib/python3.11/site-packages/pyomo/opt/base/solvers.py:718 in _convert_problem
    return convert_problem(args,

  File ~/myvenv/lib/python3.11/site-packages/pyomo/opt/base/convert.py:101 in convert_problem
    problem_files, symbol_map = converter.apply(*tmp, **tmpkw)

  File ~/myvenv/lib/python3.11/site-packages/pyomo/solvers/plugins/converter/model.py:187 in apply
    (problem_filename, symbol_map_id) = instance.write(

  File ~/myvenv/lib/python3.11/site-packages/pyomo/core/base/block.py:2016 in write
    (filename, smap) = problem_writer(self,

  File ~/myvenv/lib/python3.11/site-packages/pyomo/repn/plugins/nl_writer.py:339 in __call__
    info = self.write(model, FILE, ROWFILE, COLFILE, config=config)

  File ~/myvenv/lib/python3.11/site-packages/pyomo/repn/plugins/nl_writer.py:382 in write
    return impl.write(model)

  File ~/myvenv/lib/python3.11/site-packages/pyomo/repn/plugins/nl_writer.py:825 in write
    for v in sos.variables:

AttributeError: 'IndexedSOSConstraint' object has no attribute 'variables'
```

### Information on your system

Pyomo version: 6.5.0
Python version: 3.11.2
Operating system: debian bookworm
How Pyomo was installed: pip
Solver: SCIP 8.0.3


### Additional information

The problem exists whether or not I specify the SOS1 weights (see commented code above).

While testing, I noticed that pyomo can write problem files with SOS1 constraints in the .mps and .lp formats. However, only the latter can be (correctly) read by SCIP. In contrast, CPLEX can read both and recognise the SOS1 constraints. (I can upload sample problems on demand, though these can be generated easily using the code above)

On the other hand, I am able to solve ConcreteModel problems with non-indexed SOS1 constraints and SCIP:

```import pyomo.environ as pyo
model = pyo.ConcreteModel()

model.x = pyo.Var([1], domain=pyo.NonNegativeReals, bounds=(0,40))
model.y = pyo.Var([1,2,3], domain=pyo.NonNegativeIntegers)
model.OBJ = pyo.Objective(
    expr=(1*model.x[1]+
          2*model.y[1]+
          3*model.y[2]+
          1*model.y[3])
    )
model.ConstraintY3_lb = pyo.Constraint(expr = model.y[3] >= 2 )
model.ConstraintY3_ub = pyo.Constraint(expr = model.y[3] <= 3 )

model.mysos = pyo.SOSConstraint(var=model.y,
                                index=[2,3],
                                weights={2: 25.0, 3: 18.0},
                                sos=1)

opt = pyo.SolverFactory('scip')

opt.solve(model,tee=True)
```

### Additional contract requirements

- The public method `pyomo.repn.plugins.nl_writer.NLWriter.write(model, file, symbolic_solver_labels=False, **kwargs)` serializes a model into the AMPL NL format; when `symbolic_solver_labels=True`, variable and constraint names are emitted as symbolic labels.
- `pyomo.environ.SOSConstraint` accepts an index set as its first positional argument, together with the `var`, `sos`, `index` and `weights` keyword arguments.
- The SOS type (`sos`) may be either 1 (SOS1) or 2 (SOS2).
- Writing a model that contains an indexed SOS constraint must produce valid AMPL NL output that preserves the supplied SOS membership and reference weights.
- In the AMPL NL output, the SOS type is encoded in the sign of the `sosno` set identifier: SOS1 sets use a positive value and SOS2 sets use a negative value.
