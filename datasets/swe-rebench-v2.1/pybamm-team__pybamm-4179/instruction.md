[Bug]: "electrode diffusivity" -> "particle diffusivity" is still breaking change on `develop` when using pre-24.5 pybamm.ParameterValues
### PyBaMM Version

develop

### Python Version

3.9.13

### Describe the bug

Since #4072 re-inverted the logic fix in #3871, the release candidate on `develop` causes the rename of "electrode diffusivity" -> "particle diffusivity" to be a breaking change. Parameter sets using the old key names do not simulate in the 24.5 RC.

### Steps to Reproduce

```python
import pybamm

parameter_values = pybamm.ParameterValues("Chen2020")

# Dummy a pybamm.ParameterValues object with a legacy parameter name
parameter_values.update(
    {
        "Negative electrode diffusivity [m2.s-1]": parameter_values["Negative particle diffusivity [m2.s-1]"],
    },
    check_already_exists=False,
)
del parameter_values["Negative particle diffusivity [m2.s-1]"]

# Try to run a simulation with the old-style parameter set
model = pybamm.lithium_ion.DFN()
experiment = pybamm.Experiment(
    [
        "Discharge at 1C until 3 V",
    ]
)
sim = pybamm.Simulation(
    model,
    parameter_values=parameter_values,
    experiment=experiment,
)

# KeyError provoked here on call into pybamm.ParameterValues with new key name
sol = sim.solve()
```

### Relevant log output

_No response_

### Additional contract requirements

- When a `FuzzyDict` contains the legacy key `"Positive electrode diffusivity [m2.s-1]"`, looking up `"Positive particle diffusivity [m2.s-1]"` must return the stored value and emit a `DeprecationWarning`.
