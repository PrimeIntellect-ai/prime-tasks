Add API/Getter for Variable Bounds Expressions
## Summary

API/Getter for variable bounds expression to circumvent use of the protected `._lb` and `._ub` attributes of variable objects.

### Rationale

The module `pyomo.contrib.pyros` may require access to variable bounds expressions to determine whether these bounds are contingent on uncertain parameters, and consequently, to construct separation problem objective expressions which contain variable objects meant to simulate these uncertain parameters (as opposed to just the numerical values of the parameters). Currently, the only known way to access these variable bound expressions is through the protected `._lb` and `._ub` attributes.

### Description

See summary.


### Additional information
<!-- Add any other context about the feature request here. -->



<!-- If you want to ask a question (how to use Pyomo, what it can do, etc.), please refer to our [online documentation](https://github.com/Pyomo/pyomo#getting-help) on ways to get help. -->

### Additional contract requirements

Variables provide public `lower` and `upper` getters that return the expressions for their current lower and upper bounds, respectively. These getters let callers retrieve bound expressions without accessing protected bound storage.
