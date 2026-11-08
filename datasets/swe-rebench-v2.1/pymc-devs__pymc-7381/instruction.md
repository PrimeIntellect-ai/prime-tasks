BUG: Using a length-only coord causes it to be volatile
### Describe the issue:

When a variable is defined with a coord, it's considered volatile. Then `sample_posterior_predictive` does not transfer the node over.
I believe the volatility condition that's met is https://github.com/pymc-devs/pymc/blob/9eaf92ab40ff95cf7f5cb2763377e06bb0d7be0f/pymc/sampling/forward.py#L208-L212

The coord is intended to be immutable, but after https://github.com/pymc-devs/pymc/pull/7047, coords always mutable

Somewhat related:
- https://github.com/pymc-devs/pymc/issues/7069
- https://github.com/pymc-devs/pymc/issues/6876
- https://github.com/pymc-devs/pymc/issues/7183
(lmk if this issue is considered a duplicate of anything)

### Reproduceable code example:

```python
import pymc as pm

y_obs = [0] * 3
with pm.Model() as m:
    m.add_coord("coord0", length=1)
    x = pm.Data("x", [0] * 3)
    b = pm.Normal("b", dims="coord0")  # Causes `b` to be volatile
    # b = pm.Normal("b", shape=1)      # Works as expected (`b` is transferred)
    y = pm.Normal("y", b[0] * x, observed=y_obs)
    idata = pm.sample()

    pm.sample_posterior_predictive(trace=idata, var_names='y')
```


### Error message:

```shell
Sampling: [b, y]
```


### PyMC version information:

5.15.1

### Context for the issue:

Cannot use `sample_posterior_predictive` as intended
