jax.random.normal(key, 1000) error message is bad
Come on:

```
In [16]: jax.random.normal(jax.random.key(0), 1000)
---------------------------------------------------------------------------
TypeError                                 Traceback (most recent call last)
Cell In[16], line 1
----> 1 jax.random.normal(jax.random.key(0), 1000)

File ~/packages/jax/jax/_src/random.py:710, in normal(key, shape, dtype)
    707   raise ValueError(f"dtype argument to `normal` must be a float or complex dtype, "
    708                    f"got {dtype}")
    709 dtype = dtypes.canonicalize_dtype(dtype)
--> 710 shape = core.as_named_shape(shape)
    711 return _normal(key, shape, dtype)

File ~/packages/jax/jax/_src/core.py:2332, in as_named_shape(shape)
   2330 if isinstance(shape, NamedShape):
   2331   return shape
[HIDDEN]

TypeError: jax._src.core.NamedShape() argument after * must be an iterable, not int
```

### Additional contract requirements

- `jax.random.normal` must accept an integer `shape` as a one-dimensional output shape of that length. For example, `jax.random.normal(jax.random.key(0), 1000)` must not fail with the reported non-iterable `NamedShape` `TypeError`.
