Incorrect Jacobian of `jax.scipy.special.logsumexp` when `b` contains a `0`
### Description

The gradient of `jax.scipy.special.logsumexp` along `b` is wrong when `b` contains a `0`. In the following example, the gradient of $f(x_1, x_2) = \log(x_1 + x_2)$ should be:
```math
\nabla_x f(x) = \left( \frac{1}{x_1 + x_2}, \frac{1}{x_1 + x_2} \right)
```
but JAX outputs that the gradient at `(1,0)` is `(1,0)` when it should be `(1,1)`:

```python
import jax
import jax.numpy as jnp

fun = lambda x: jax.scipy.special.logsumexp(jnp.zeros(2), axis=0, b=x)
a = jnp.array([1, 0], dtype=float)

jax.jacfwd(fun)(a)
```
output:
```python
Array([1., 0.], dtype=float32)
```


There is only a problem for an exact `0`: the gradient taken at `(1,1e-30)` outputs the correct value of `(1,1)`:
```python
a = jnp.array([1, 1e-30], dtype=float)
jax.jacfwd(fun)(a)
```
output:
```python
Array([1., 1.], dtype=float32)
```


Furthermore, if the `logsumexp` is implemented manually, the gradient at `(1, 0)` is also correct:
```python
fun_2 = lambda x: jnp.log(jnp.sum(x * jnp.exp(jnp.zeros(2))))
a = jnp.array([1, 0], dtype=float)
jax.jacfwd(fun_2)(a)
```
output:
```python
Array([1., 1.], dtype=float32)
```

cc @PhilipVinc

### System info (python version, jaxlib version, accelerator, etc.)

```
jax:    0.4.30
jaxlib: 0.4.30
numpy:  1.24.4
python: 3.11.6 | packaged by conda-forge | (main, Oct  3 2023, 10:37:07) [Clang 15.0.7 ]
jax.devices (1 total, 1 local): [CpuDevice(id=0)]
process_count: 1
platform: uname_result(system='Darwin', node='mba-10836208', release='23.4.0', version='Darwin Kernel Version 23.4.0: Fri Mar 15 00:19:22 PDT 2024; root:xnu-10063.101.17~1/RELEASE_ARM64_T8112', machine='arm64')
```
