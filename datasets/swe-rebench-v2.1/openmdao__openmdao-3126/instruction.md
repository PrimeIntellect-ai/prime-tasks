Residual scaling not accounted for in matrix-free partial derivatives
### Description

When the residuals of an implicit component are scaled (for example using the `res_ref` argument to `add_output`), the partial derivatives computed through the matrix-free API are not modified to account for this scaling as they are through the standard API.

### Example

I've been able to recreate this issue in the circuit analysis example from the OpenMDAO docs. Below is the script I am using, where I've added an `apply_linear` method to the node component and scaled it's residuals by a factor 1000 (using `, res_ref=1e-3`).

```python
import numpy as np

import openmdao.api as om


class Resistor(om.ExplicitComponent):
    """Computes current across a resistor using Ohm's law."""

    def initialize(self):
        self.options.declare("R", default=1.0, desc="Resistance in Ohms")

    def setup(self):
        self.add_input("V_in", units="V")
        self.add_input("V_out", units="V")
        self.add_output("I", units="A")

        # partial derivs are constant, so we can assign their values in setup
        R = self.options["R"]
        self.declare_partials("I", "V_in", val=1 / R)
        self.declare_partials("I", "V_out", val=-1 / R)

    def compute(self, inputs, outputs):
        deltaV = inputs["V_in"] - inputs["V_out"]
        outputs["I"] = deltaV / self.options["R"]


class Diode(om.ExplicitComponent):
    """Computes current across a diode using the Shockley diode equation."""

    def initialize(self):
        self.options.declare("Is", default=1e-15, desc="Saturation current in Amps")
        self.options.declare("Vt", default=0.025875, desc="Thermal voltage in Volts")

    def setup(self):
        self.add_input("V_in", units="V")
        self.add_input("V_out", units="V")
        self.add_output("I", units="A")

        # non-linear component, so we'll declare the partials here but compute them in compute_partials
        self.declare_partials("I", "V_in")
        self.declare_partials("I", "V_out")

    def compute(self, inputs, outputs):
        deltaV = inputs["V_in"] - inputs["V_out"]
        Is = self.options["Is"]
        Vt = self.options["Vt"]
        outputs["I"] = Is * (np.exp(deltaV / Vt) - 1)

    def compute_partials(self, inputs, J):
        deltaV = inputs["V_in"] - inputs["V_out"]
        Is = self.options["Is"]
        Vt = self.options["Vt"]
        I = Is * np.exp(deltaV / Vt)

        J["I", "V_in"] = I / Vt
        J["I", "V_out"] = -I / Vt


class Node(om.ImplicitComponent):
    """Computes voltage residual across a node based on incoming and outgoing current."""

    def initialize(self):
        self.options.declare("n_in", default=1, types=int, desc="number of connections with + assumed in")
        self.options.declare("n_out", default=1, types=int, desc="number of current connections + assumed out")

    def setup(self):
        self.add_output("V", val=5.0, units="V", res_ref=1e-3)

        for i in range(self.options["n_in"]):
            i_name = "I_in:{}".format(i)
            self.add_input(i_name, units="A")

        for i in range(self.options["n_out"]):
            i_name = "I_out:{}".format(i)
            self.add_input(i_name, units="A")

            # note: we don't declare any partials wrt `V` here,
            #      because the residual doesn't directly depend on it

    def apply_nonlinear(self, inputs, outputs, residuals):
        residuals["V"] = 0.0
        for i_conn in range(self.options["n_in"]):
            residuals["V"] += inputs["I_in:{}".format(i_conn)]
        for i_conn in range(self.options["n_out"]):
            residuals["V"] -= inputs["I_out:{}".format(i_conn)]

    def apply_linear(self, inputs, outputs, d_inputs, d_outputs, d_residuals, mode):
        if mode == "fwd":
            for i_conn in range(self.options["n_in"]):
                d_residuals["V"] += d_inputs["I_in:{}".format(i_conn)]
            for i_conn in range(self.options["n_out"]):
                d_residuals["V"] -= d_inputs["I_out:{}".format(i_conn)]

        if mode == "rev":
            for i_conn in range(self.options["n_in"]):
                d_inputs["I_in:{}".format(i_conn)] += d_residuals["V"]
            for i_conn in range(self.options["n_out"]):
                d_inputs["I_out:{}".format(i_conn)] -= d_residuals["V"]


class Circuit(om.Group):
    def setup(self):
        self.add_subsystem("n1", Node(n_in=1, n_out=2), promotes_inputs=[("I_in:0", "I_in")])
        self.add_subsystem("n2", Node())  # leaving defaults

        self.add_subsystem("R1", Resistor(R=100.0), promotes_inputs=[("V_out", "Vg")])
        self.add_subsystem("R2", Resistor(R=10000.0))
        self.add_subsystem("D1", Diode(), promotes_inputs=[("V_out", "Vg")])

        self.connect("n1.V", ["R1.V_in", "R2.V_in"])
        self.connect("R1.I", "n1.I_out:0")
        self.connect("R2.I", "n1.I_out:1")

        self.connect("n2.V", ["R2.V_out", "D1.V_in"])
        self.connect("R2.I", "n2.I_in:0")
        self.connect("D1.I", "n2.I_out:0")

        self.nonlinear_solver = om.NewtonSolver()
        self.linear_solver = om.ScipyKrylov()

        self.nonlinear_solver.options["iprint"] = 2
        self.nonlinear_solver.options["maxiter"] = 10
        self.nonlinear_solver.options["solve_subsystems"] = True
        self.nonlinear_solver.linesearch = om.ArmijoGoldsteinLS()
        self.nonlinear_solver.linesearch.options["maxiter"] = 10
        self.nonlinear_solver.linesearch.options["iprint"] = 2


p = om.Problem()
model = p.model

model.add_subsystem("circuit", Circuit())

p.setup(force_alloc_complex=True)

p.set_val("circuit.I_in", 0.1)
p.set_val("circuit.Vg", 0.0)

# set some initial guesses
p.set_val("circuit.n1.V", 10.0)
p.set_val("circuit.n2.V", 1e-3)

p.run_model()

print(p["circuit.n1.V"])
print(p["circuit.n2.V"])
print(p["circuit.R1.I"])
print(p["circuit.R2.I"])
print(p["circuit.D1.I"])

# sanity check: should sum to .1 Amps
print(p["circuit.R1.I"] + p["circuit.D1.I"])

p.check_partials(compact_print=True, method="cs", step=1e-200)
```

Without scaling the residual, the check_partials results are perfect:

```
----------------------------
Component: Node 'circuit.n1'
----------------------------

+-----------------+------------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+------------+
| of '<variable>' | wrt '<variable>' |    fwd mag. |    rev mag. |  check mag. |  a(fwd-chk) |  a(rev-chk) |  a(fwd-rev) |  r(fwd-chk) |  r(rev-chk) |  r(fwd-rev) | error desc |
+=================+==================+=============+=============+=============+=============+=============+=============+=============+=============+=============+============+
| 'V'             | 'I_in:0'         |  1.0000e+00 |  1.0000e+00 |  1.0000e+00 |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |            |
+-----------------+------------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+------------+
| 'V'             | 'I_out:0'        |  1.0000e+00 |  1.0000e+00 |  1.0000e+00 |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |            |
+-----------------+------------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+------------+
| 'V'             | 'I_out:1'        |  1.0000e+00 |  1.0000e+00 |  1.0000e+00 |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |            |
+-----------------+------------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+------------+
| 'V'             | 'V'              |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |         nan |         nan |         nan |            |
+-----------------+------------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+------------+
```

With the scaling, the residual partial derivatives are off by exactly the residual scaling factor:
```
----------------------------
Component: Node 'circuit.n1'
----------------------------

+-----------------+------------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+--------------------+
| of '<variable>' | wrt '<variable>' |    fwd mag. |    rev mag. |  check mag. |  a(fwd-chk) |  a(rev-chk) |  a(fwd-rev) |  r(fwd-chk) |  r(rev-chk) |  r(fwd-rev) | error desc         |
+=================+==================+=============+=============+=============+=============+=============+=============+=============+=============+=============+====================+
| 'V'             | 'I_in:0'         |  1.0000e+03 |  1.0000e-03 |  1.0000e+00 |  9.9900e+02 |  9.9900e-01 |  1.0000e+03 |  9.9900e+02 |  9.9900e-01 |  1.0000e+03 |  >ABS_TOL >REL_TOL |
+-----------------+------------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+--------------------+
| 'V'             | 'I_out:0'        |  1.0000e+03 |  1.0000e-03 |  1.0000e+00 |  9.9900e+02 |  9.9900e-01 |  1.0000e+03 |  9.9900e+02 |  9.9900e-01 |  1.0000e+03 |  >ABS_TOL >REL_TOL |
+-----------------+------------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+--------------------+
| 'V'             | 'I_out:1'        |  1.0000e+03 |  1.0000e-03 |  1.0000e+00 |  9.9900e+02 |  9.9900e-01 |  1.0000e+03 |  9.9900e+02 |  9.9900e-01 |  1.0000e+03 |  >ABS_TOL >REL_TOL |
+-----------------+------------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+--------------------+
| 'V'             | 'V'              |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |  0.0000e+00 |         nan |         nan |         nan |                    |
+-----------------+------------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+--------------------+
```


### OpenMDAO Version

3.29.1-dev

### Relevant environment information

_No response_
