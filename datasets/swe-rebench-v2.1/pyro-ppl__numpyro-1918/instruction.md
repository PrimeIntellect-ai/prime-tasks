`MCMC.run` gets error after `MCMC.warmup` with `AIES`
Hi, I get an error when I `MCMC.run` after `warmup` with `AIES`.
Here is the example
```
import jax
import jax.numpy as jnp
import numpyro
from numpyro.infer import MCMC, AIES
import numpyro.distributions as dist

n_dim, num_chains = 5, 100
mu, sigma = jnp.zeros(n_dim), jnp.ones(n_dim)

def model(mu, sigma):
    with numpyro.plate('n_dim', n_dim):
        numpyro.sample("x", dist.Normal(mu, sigma))

kernel = AIES(model, moves={AIES.DEMove() : 0.5,
                            AIES.StretchMove() : 0.5})

mcmc = MCMC(kernel,
            num_warmup=100,
            num_samples=100,
            num_chains=num_chains,
            chain_method='vectorized')

mcmc.warmup(jax.random.PRNGKey(0), mu, sigma)
mcmc.run(jax.random.PRNGKey(1), mu, sigma)
```
The error
```
{
	"name": "ValueError",
	"message": "split accepts a single key, but was given a key array of shape (100, 2) != (). Use jax.vmap for batching.",
	"stack": "---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
Cell In[13], line 26
     18 mcmc = MCMC(kernel,
     19             num_warmup=100,
     20             num_samples=100,
     21             num_chains=num_chains,
     22             chain_method='vectorized')
     25 mcmc.warmup(jax.random.PRNGKey(0), mu, sigma)
---> 26 mcmc.run(jax.random.PRNGKey(1), mu, sigma)

File ~/anaconda3/lib/python3.11/site-packages/numpyro/infer/mcmc.py:675, in MCMC.run(self, rng_key, extra_fields, init_params, *args, **kwargs)
    673 else:
    674     assert self.chain_method == \"vectorized\"
--> 675     states, last_state = partial_map_fn(map_args)
    676     # swap num_samples x num_chains to num_chains x num_samples
    677     states = tree_map(lambda x: jnp.swapaxes(x, 0, 1), states)

File ~/anaconda3/lib/python3.11/site-packages/numpyro/infer/mcmc.py:462, in MCMC._single_chain_mcmc(self, init, args, kwargs, collect_fields, remove_sites)
    456 collection_size = self._collection_params[\"collection_size\"]
    457 collection_size = (
    458     collection_size
    459     if collection_size is None
    460     else collection_size // self.thinning
    461 )
--> 462 collect_vals = fori_collect(
    463     lower_idx,
    464     upper_idx,
    465     sample_fn,
    466     init_val,
    467     transform=_collect_fn(collect_fields, remove_sites),
    468     progbar=self.progress_bar,
    469     return_last_val=True,
    470     thinning=self.thinning,
    471     collection_size=collection_size,
    472     progbar_desc=partial(_get_progbar_desc_str, lower_idx, phase),
    473     diagnostics_fn=diagnostics,
    474     num_chains=self.num_chains if self.chain_method == \"parallel\" else 1,
    475 )
    476 states, last_val = collect_vals
    477 # Get first argument of type `HMCState`

File ~/anaconda3/lib/python3.11/site-packages/numpyro/util.py:367, in fori_collect(lower, upper, body_fun, init_val, transform, progbar, return_last_val, collection_size, thinning, **progbar_opts)
    365 with tqdm.trange(upper) as t:
    366     for i in t:
--> 367         vals = jit(_body_fn)(i, vals)
    368         t.set_description(progbar_desc(i), refresh=False)
    369         if diagnostics_fn:

    [... skipping hidden 11 frame]

File ~/anaconda3/lib/python3.11/site-packages/numpyro/util.py:332, in fori_collect.<locals>._body_fn(i, vals)
    329 @cached_by(fori_collect, body_fun, transform)
    330 def _body_fn(i, vals):
    331     val, collection, start_idx, thinning = vals
--> 332     val = body_fun(val)
    333     idx = (i - start_idx) // thinning
    334     collection = cond(
    335         idx >= 0,
    336         collection,
   (...)
    339         identity,
    340     )

File ~/anaconda3/lib/python3.11/site-packages/numpyro/infer/mcmc.py:188, in _sample_fn_nojit_args(state, sampler, args, kwargs)
    186 def _sample_fn_nojit_args(state, sampler, args, kwargs):
    187     # state is a tuple of size 1 - containing HMCState
--> 188     return (sampler.sample(state[0], args, kwargs),)

File ~/anaconda3/lib/python3.11/site-packages/numpyro/infer/ensemble.py:192, in EnsembleSampler.sample(self, state, model_args, model_kwargs)
    190 def sample(self, state, model_args, model_kwargs):
    191     z, inner_state, rng_key = state
--> 192     rng_key, _ = random.split(rng_key)
    193     z_flat, unravel_fn = batch_ravel_pytree(z)
    195     if self._randomize_split:

File ~/anaconda3/lib/python3.11/site-packages/jax/_src/random.py:285, in split(key, num)
    274 def split(key: KeyArrayLike, num: int | tuple[int, ...] = 2) -> KeyArray:
    275   \"\"\"Splits a PRNG key into `num` new keys by adding a leading axis.
    276
    277   Args:
   (...)
    283     An array-like object of `num` new PRNG keys.
    284   \"\"\"
--> 285   typed_key, wrapped = _check_prng_key(\"split\", key, error_on_batched=True)
    286   return _return_prng_keys(wrapped, _split(typed_key, num))

File ~/anaconda3/lib/python3.11/site-packages/jax/_src/random.py:108, in _check_prng_key(name, key, allow_batched, error_on_batched)
    105 msg = (f\"{name} accepts a single key, but was given a key array of \"
    106        f\"shape {np.shape(key)} != (). Use jax.vmap for batching.\")
    107 if error_on_batched:
--> 108   raise ValueError(msg)
    109 else:
    110   warnings.warn(msg + \" In a future JAX version, this will be an error.\",
    111                 FutureWarning, stacklevel=3)

ValueError: split accepts a single key, but was given a key array of shape (100, 2) != (). Use jax.vmap for batching."
```

It will get the same error if use `ESS`
