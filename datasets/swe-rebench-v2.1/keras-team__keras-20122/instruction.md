SVD operation failed when compute_uv=False (TF backend)
### Problem raised

TensorFlow `tf.linalg.svd()` with compute_uv=False returns a single tensor containing the singular values, and not three tensors "s, u, v" when compute_uv=True.
[HIDDEN] It raises a ValueError: not enough values to unpack.
https://github.com/keras-team/keras/blob/6abd865eaa1af31d8fc60a573992a9e75f570bb8/keras/src/backend/tensorflow/linalg.py#L188)

### Tested versions:

- Keras 3.4.1
- TensorFlow 2.17.0

### Code to reproduce:

```python
import keras
keras.ops.svd([[1.0, 0.0], [2.0, 0.0]], compute_uv=False)
```

### Additional contract requirements

- On the TensorFlow backend, `keras.ops.svd(x, compute_uv=False)` returns the singular values of `x`, the same values as the `s` output of `keras.ops.svd(x)`, without raising an error.
