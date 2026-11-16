Increase default r_pts
I think we should increase the default r_pts from 10. E.g.
```python3
import pybamm
import numpy as np

model = pybamm.lithium_ion.DFN()

chemistry = pybamm.parameter_sets.Ecker2015
parameter_values = pybamm.ParameterValues(chemistry=chemistry)

var = pybamm.standard_spatial_vars
npts = [10, 20, 25, 30, 40, 50]

solver = pybamm.CasadiSolver(mode="fast")
t_eval = np.linspace(0, 3800, 200)

sols = []
for N in npts:
    var_pts = {var.x_n: 20, var.x_s: 20, var.x_p: 20, var.r_n: N, var.r_p: N}
    sim = pybamm.Simulation(
        model, solver=solver, parameter_values=parameter_values, var_pts=var_pts
    )
    sol = sim.solve(t_eval=t_eval)
    print("N={}: {} s".format(N, sol.solve_time))
    sols.append(sol)

pybamm.dynamic_plot(sols, ["Terminal voltage [V]"], time_unit="seconds", labels=npts)
```

gives

N=10: 0.15861007800413063 s
N=20: 0.235911022995424 s
N=25: 0.29073380999761866 s
N=30: 0.31032642299396684 s
N=40: 0.4951283990012598 s
N=50: 0.5220356229983736 s


![Figure_2](https://user-images.githubusercontent.com/43040151/85523692-37762900-b5ff-11ea-9139-933e013cc036.png)

My vote would be somewhere between 20 and 30
