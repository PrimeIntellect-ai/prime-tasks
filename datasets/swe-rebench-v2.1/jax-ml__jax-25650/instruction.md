arr.view fails with int4
```python
>>> import jax.numpy as jnp
>>> x = jnp.arange(4).astype('int4')
>>> x.view('int16')
---------------------------------------------------------------------------
MLIRError                                 Traceback (most recent call last)
File ~/github/google/jax/jax/_src/interpreters/mlir.py:1211, in lower_jaxpr_to_module(***failed resolving arguments***)
   1210 try:
-> 1211   if not ctx.module.operation.verify():
   1212     raise ValueError(
   1213         "Cannot lower jaxpr with verifier errors. " +
   1214         dump_module_message(ctx.module, "verification"))

MLIRError: Verification failed:
<...>
```
I believe that XLA can handle this, but currently we're choosing our lowering shapes based on `dtype.itemsize`, and `np.dtype('int4').itemsize` returns `1` due to limitations of the NumPy dtype API.

I think we can fix this by [HIDDEN].

### Additional contract requirements

- Calling `.view('int16')` on the `int4` array in the reproduction must succeed and correctly reinterpret its data, without failing during lowering or MLIR verification.
- More generally, views of `int4` arrays to other supported, shape-compatible dtypes must preserve the total bit content and produce the corresponding output shape, rather than failing because the dtype's byte-rounded itemsize misrepresents its bit width.
