Running a model with only linear constraints raises error in relevance check
### Description

If a model is created that has had linear constraints added but no objective or nonlinear constraints, then calling `run_model()` fails due to an array indexing error inside a call to `is_relevant` during `final_setup`.


### Example

Here is a minimal example that throws the error

```python
import numpy as np
import openmdao.api as om

# A very simple OpenMDAO example that solves an underdetermined linear system
# by minimising the L2 norm of x subject to the constraint Ax = b


class LinearEquation(om.ExplicitComponent):
    """A linear equation y = Ax - b"""

    def initialize(self):
        self.options.declare("numInputs", types=int, default=3)
        self.options.declare("numOutputs", types=int, default=2)

    def setup(self):
        np.random.seed(0)
        nIn = self.options["numInputs"]
        nOut = self.options["numOutputs"]
        self.A = np.random.rand(nOut, nIn)
        self.b = np.random.rand(nOut)
        self.add_input("x", shape=nIn)
        self.add_output("res", shape=nOut)

        self.declare_partials("res", "x", val=self.A)

    def compute(self, inputs, outputs):
        outputs["res"] = self.A @ inputs["x"] - self.b


class SquaredNorm(om.ExplicitComponent):
    """The square of the L2 norm of a vector"""

    def initialize(self):
        self.options.declare("numInputs", types=int, default=3)

    def setup(self):
        nIn = self.options["numInputs"]
        self.add_input("x", shape=nIn)
        self.add_output("xNorm")

        self.declare_partials("xNorm", "x")

    def compute_partials(self, inputs, partials):
        partials["xNorm", "x"] = 2 * inputs["x"]

    def compute(self, inputs, outputs):
        outputs["xNorm"] = np.dot(inputs["x"], inputs["x"])


class UnderdeterminedSystem(om.Group):
    def initialize(self):
        self.options.declare("numInputs", types=int, default=3)
        self.options.declare("numOutputs", types=int, default=2)

    def setup(self):
        nIn = self.options["numInputs"]
        nOut = self.options["numOutputs"]

        variables = om.IndepVarComp("x", np.random.rand(nIn))
        self.add_subsystem("variables", variables, promotes=["*"])
        self.add_design_var("x")

        self.add_subsystem("linearEquation", LinearEquation(numInputs=nIn, numOutputs=nOut), promotes=["*"])
        self.add_constraint("linearEquation.res", equals=0.0, linear=True)

        self.add_subsystem("norm2", SquaredNorm(numInputs=nIn), promotes=["*"])
        # self.add_objective("xNorm") # Uncomment this line to not have an error


prob = om.Problem(model=UnderdeterminedSystem(numInputs=3, numOutputs=2))
prob.setup()
om.n2(prob)
prob.run_model()
```

```
$ python linConTest.py
Traceback (most recent call last):
  File "/home/ali/Desktop/OpenMDAO-NLBGS-Debugging/linConTest.py", line 73, in <module>
    prob.run_model()
  File "/home/ali/repos/OpenMDAO/openmdao/core/problem.py", line 668, in run_model
    self.final_setup()
  File "/home/ali/repos/OpenMDAO/openmdao/utils/hooks.py", line 372, in __call__
    ret = self.func(*args, **kwargs)
  File "/home/ali/repos/OpenMDAO/openmdao/core/problem.py", line 1088, in final_setup
    driver._setup_driver(self)
  File "/home/ali/repos/OpenMDAO/openmdao/core/driver.py", line 451, in _setup_driver
    self._split_dvs(model)
  File "/home/ali/repos/OpenMDAO/openmdao/core/driver.py", line 606, in _split_dvs
    self._nl_dvs = {dv: meta for dv, meta in self._designvars.items()
  File "/home/ali/repos/OpenMDAO/openmdao/core/driver.py", line 607, in <dictcomp>
    if relevance.is_relevant(meta['source'])}
  File "/home/ali/repos/OpenMDAO/openmdao/utils/relevance.py", line 845, in is_relevant
    return self._current_rel_varray[self._var2idx[name]]
IndexError: index 4 is out of bounds for axis 0 with size 0
```

### OpenMDAO Version

3.34.3.dev0 (master branch commit f4b1e8455c6beea5d49f218343e31a9c80cf8574)

### Relevant environment information

_No response_
