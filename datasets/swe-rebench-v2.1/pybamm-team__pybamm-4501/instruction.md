add `DiscreteTimeSum` subclass of `pybamm.Symbol`
### Description

This would add a new unary operator in a pybamm expression tree that would represent a discrete sum over time. This would be a discrete version of the already existing `pybamm.ExplicitTimeIntegral` class.

### Motivation

This would give model developers and users the ability to add "sum of squares" type variables to a pybamm model that would calculate the difference between, for example, a solution variable and a user-provided dataset. This would be useful for implementing parameter inference using pybamm



### Possible Implementation

Similar to the `ExplicitTimeIntegral`, this would only be evaluated in the `Solution` class (see `_update_variable` function). I would propose that the sum is done over the list of time points in the solution (rather than have a separate list of points in the expression tree node), that way a user can specify the time-points via `t_interp`.

I'm a bit unsure how to allow users to provide their data to the expression. Perhaps they would wrap it in an Interpolant:

```python
data = pybamm.Interpolant(data_t, data_y, pybamm.t)
model.variable["data_comparison"] = pybamm.DiscreteTimeSum((model.variable["Voltage"] - data)**2)
```

### Additional context

see https://github.com/pybop-team/PyBOP/issues/513
