Sampling with generators as seeding no longer deterministic
### Description

This was revealed in https://github.com/pymc-labs/pymc-marketing/pull/1269

```python
import numpy as np
import pymc as pm

with pm.Model() as m:
    x = pm.Normal("x")

    post1 = pm.sample(tune=10, draws=10, random_seed=np.random.default_rng(42)).posterior
    post2 = pm.sample(tune=10, draws=10, random_seed=np.random.default_rng(42)).posterior
assert post1.equals(post2), (post1["x"].mean().item(), post2["x"].mean().item())
# AssertionError: (0.22006495904628473, -0.31090965213192406)
```
