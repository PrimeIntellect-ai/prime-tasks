[Bug]: pybamm.DiscreteTimeSum sensitivities not being summed over time
### PyBaMM Version

develop

### Python Version

3.10

### Describe the bug

When calculating the sensitivities for the `pybamm.DiscreteTimeSum`, the sum over time isn't being performed, giving a sensitivity vector of the same dimension as the number of time points. This is unsuprising since this is not currently being tested either, so tests and a fix are needed

### Steps to Reproduce

create a model with a variable using `pybamm.DiscreteTimeSum`, then calculate the sensitivities and check the dimension of the result

### Relevant log output

```shell

```
