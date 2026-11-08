Move jax.nn.log_softmax to jax.scipy.special?
It's in SciPy now, so it seems like the logical place for it?

### Additional contract requirements

- `jax.scipy.special.log_softmax` must be available and, when called with an explicit `axis` (an int or a tuple of ints), return the same values as `jax.nn.log_softmax` called with that same `axis`.
