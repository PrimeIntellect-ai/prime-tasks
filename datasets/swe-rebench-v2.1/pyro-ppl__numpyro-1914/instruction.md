MCMC returns no samples when model contains deterministic variables only
# Steps to reproduce

```python
from jax import numpy as jnp
from numpyro import sample, deterministic, distributions as dist

def test_model():
    x = deterministic('x', jnp.array([1.0, 2.0]))

mcmc = MCMC(NUTS(test_model), num_warmup=1000, num_samples=1000)
    mcmc.run(random.PRNGKey(0))
    samples = mcmc.get_samples()

samples # {}
mcmc.print_summary() # ERROR
```

# Expected behaviour
`samples` should contain `x`, an array of shape `(1000, 2)`.

# Observed behaviour
`samples` is `{}`. Unrelated to this, `mcmc.print_summary()` is not able to deal with `samples` being empty.

```
in print_summary(samples, prob, group_by_chain)
    296 summary_dict = summary(samples, prob, group_by_chain=True)
    298 row_names = {
    299     k: k + "[" + ",".join(map(lambda x: str(x - 1), v.shape[2:])) + "]"
    300     for k, v in samples.items()
    301 }
--> 302 max_len = max(max(map(lambda x: len(x), row_names.values())), 10)
    303 name_format = "{:>" + str(max_len) + "}"
    304 header_format = name_format + " {:>9}" * 7

ValueError: max() iterable argument is empty
```
