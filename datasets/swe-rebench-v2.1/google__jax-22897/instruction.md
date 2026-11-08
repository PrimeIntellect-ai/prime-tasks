JAX indexing should support zero-dimensional boolean masks
NumPy supports this:

```python
>>> import numpy as np
>>> x = np.arange(3)
>>> m = np.array([], dtype=bool)
>>> x[m]
array([], dtype=int64)

>>> x = np.arange(12).reshape(3, 4)
>>> m = np.empty((3, 0), dtype=bool)
>>> x[m]
array([], dtype=int64)
```

JAX does not:
```python

>>> import jax.numpy as jnp
>>> x = jnp.arange(3)
>>> m = jnp.array([], dtype=bool)
>>> x[m]
IndexError: boolean index did not match shape of indexed array in index 0: got (0,), expected (3,)

>>> x = jnp.arange(12).reshape(3, 4)
>>> m = jnp.empty((3, 0), dtype=bool)
>>> x[m]
IndexError: boolean index did not match shape of indexed array in index 0: got (3, 0), expected (3, 4)
```
This behavior also appears to be required by the [Array API specification: Boolean Array Indexing](https://data-apis.org/array-api/latest/API_specification/indexing.html#boolean-array-indexing):

> - The size of each dimension in `B` must equal the size of the corresponding dimension in `A` or be `0`, beginning with the first dimension in `A`. If a dimension size does not equal the size of the corresponding dimension in `A` and is not `0`, then an `IndexError` exception must be raised.
