Implement model transform to remove minibatching operations from graph
### Description

When using `pm.Minibatch`, the `pm.sample_posterior_predictive` returns predictions with the size of the minibatch instead of the full dataset size. To make predictions on the full dataset requires the previous trace to be passed into a new model with a similar setup. For complicated models, this would add several lines of code to create a new model that is almost identical to the previous model.

This enhancement would make it easier to perform posterior predictive checks when using minibatch.

relates to: https://discourse.pymc.io/t/minibatch-not-working/14061/10

### Example scenario:

```python
import numpy as np
import pymc as pm
import arviz as az
import pytensor.tensor as pt

# generate data
N = 10000
P = 3
rng = np.random.default_rng(88)
X_full = rng.uniform(2, 10, size=(N, 3))
beta = np.array([1.5, 0.2, -0.9])
y_full = np.matmul(X_full, beta) + rng.normal(0, 1, size=(N,))
```


### Before:

```python
# minibatch
X_mb, y_mb = pm.Minibatch(X_full, y_full, batch_size=100)

# original minibatch model
with pm.Model() as model_mb:
    b = pm.Normal("b", mu=0, sigma=3, shape=(P,))
    sigma = pm.HalfCauchy("sigma", 1)
    mu = pm.Deterministic("mu", pt.matmul(X_mb, b))
    likelihood = pm.Normal(
        "likelihood", mu=mu, sigma=sigma, observed=y_mb, total_size=N
    )

    fit_mb = pm.fit(
        n=100000,
        method="advi",
        progressbar=True,
        callbacks=[pm.callbacks.CheckParametersConvergence()],
        random_seed=88,
    )
    idata_mb = fit_mb.sample(500)

    pm.sample_posterior_predictive(idata_mb, extend_inferencedata=True)
    idata_mb.posterior = pm.compute_deterministics(
        idata_mb.posterior, merge_dataset=True
    )

# new but similar model to the original
with pm.Model() as model_preds:
    X = pm.Data("X", X_full)
    y = pm.Data("y", y_full)

    b = pm.Normal("b", mu=0, sigma=3, shape=(P,))
    sigma = pm.HalfCauchy("sigma", 1)
    mu = pm.Deterministic("mu", pt.matmul(X, b))
    likelihood = pm.Normal("likelihood", mu=mu, sigma=sigma, observed=y)

with model_preds:
    pm.set_data({"X": X_full})
    ypreds = pm.sample_posterior_predictive(idata_mb)

print(f"Minibatch: {idata_mb.posterior_predictive.likelihood.sizes}")
print(f"Full Data: {ypreds.posterior_predictive.likelihood.sizes}")

# output
Minibatch: Frozen({'chain': 1, 'draw': 500, 'likelihood_dim_2': 100})
Full Data: Frozen({'chain': 1, 'draw': 500, 'likelihood_dim_2': 10000})
```

### Additional contract requirements

- Provide `remove_minibatched_nodes(model)` in `pymc.model.transform.basic`. It accepts a PyMC model that may contain `pm.Minibatch` operations and returns a model whose minibatch outputs are replaced by the corresponding full input data, so downstream variables have full-dataset dimensions. Preserve the model’s coordinates and dimension-length metadata.
