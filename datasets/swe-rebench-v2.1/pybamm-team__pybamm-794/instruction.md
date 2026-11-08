Solution[<variable>] doesn't work when some parameters are inputs
**Describe the bug**
The inputs are not making their way to all the things that need to be evaluated somehow. The example below will work if current is the only input but fails when electrode height is one. Something to do with mesh

**To Reproduce**
```
import pybamm
import numpy as np

pybamm.set_logging_level('DEBUG')

I_typical = 1.0

def current_function(t):
    return pybamm.InputParameter("Current")

model = pybamm.lithium_ion.SPM()
geometry = model.default_geometry
param = model.default_parameter_values
param.update(
    {
        "Typical current [A]": I_typical,
        "Current function [A]": current_function,
        "Current": "[input]",
        "Electrode height [m]": "[input]",
    }
)
param.process_model(model)
param.process_geometry(geometry)
var = pybamm.standard_spatial_vars
var_pts = {var.x_n: 5, var.x_s: 5, var.x_p: 5, var.r_n: 10, var.r_p: 10}
spatial_methods = model.default_spatial_methods

solver = model.default_solver
sim = pybamm.Simulation(
    model=model,
    geometry=geometry,
    parameter_values=param,
    var_pts=var_pts,
    spatial_methods=spatial_methods,
    solver=solver,
)

inputs = {
        'Current': I_typical,
        'Electrode height [m]': 0.1
        }

sim.solve(t_eval=np.linspace(0, 0.01, 100), inputs=inputs)
print(sim.solution['Time [h]'](sim.solution.t))
```
