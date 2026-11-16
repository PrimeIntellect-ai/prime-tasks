[Bug]: [24.5rc0] Simulations with `pybamm.Experiment` terminate after 24 h
### PyBaMM Version

24.5rc0

### Python Version

3.9.13

### Describe the bug

Simulations using `pybamm.Experiment` with a voltage cut-off only appear to terminate with a time cut-off after 24 h.

I'm afraid I haven't had time to get into logs to figure out why this is happening!

### Steps to Reproduce

The following simulation should proceed for approximately 100 h = 360000 s, until the specified voltage cut-off. However, it terminates after 24 h.

```python
import pybamm

parameter_values = pybamm.ParameterValues("Chen2020")
model = pybamm.lithium_ion.DFN()
experiment = pybamm.Experiment(
    [
        "Discharge at 0.01C until 2.5 V",
    ]
)

sim = pybamm.Simulation(
    model,
    parameter_values=parameter_values,
    experiment=experiment,
)

sol = sim.solve()
sim.plot()

print(f'Last time step at {sim.solution["Time [s]"].entries[-1] / 3600} h')
```

### Relevant log output

_No response_
