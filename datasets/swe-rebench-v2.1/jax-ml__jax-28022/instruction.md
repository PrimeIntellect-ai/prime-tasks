bernoulli samples fail for small probabilities
Example:
```python
import jax

key = jax.random.key(0)
samples = jax.random.bernoulli(key, p=1E-10, shape=int(1E8))
print(samples.sum())  # should be zero with high probability
# 7
```
The issue is that at float32, uniform values have a resolution of $2^{-23}$ which is about $10^{-7}$, and so we don't have the resolution to properly evaluate samples with `p` smaller than about `1E-7`.

We could make this better by [HIDDEN], though that would only get us to `p` of about `2E-10`. By [HIDDEN] we could get to `4E-10`.

### Additional contract requirements

- Bernoulli sampling should support probabilities below the approximate `1E-7` float32 uniform-resolution limit described above, rather than being limited by that resolution.
- For the exact invocation shown above with `key = jax.random.key(0)`, `p=1E-10`, and `shape=int(1E8)`, `samples.sum()` must equal `0`.
