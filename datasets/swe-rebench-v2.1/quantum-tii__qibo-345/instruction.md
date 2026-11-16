Controlled by gates with density matrices
**Describe the bug**
Controlled gates that are created using the `controlled_by` method do not work with density matrices of 5 or more qubits if the `defaulteinsum` or `matmuleinsum` Tensorflow backends are used.

**To Reproduce**
```Python
import qibo
from qibo import gates, models
qibo.set_backend("defaulteinsum")

c = models.Circuit(5, density_matrix=True)
c.add(gates.H(1).controlled_by(0))
result = c()
```
leads to the following Tensorflow error:

```tensorflow.python.framework.errors_impl.UnimplementedError: Unhandled input dimensions 10 [Op:StridedSlice] name: strided_slice/```

The issue appears only for 5 or more qubits and only with the native tensorflow backends only. The numpy backends and the custom backend work without problem.

### Additional contract requirements

- The backend interface (`AbstractBackend` in `src/qibo/backends/abstract.py`) exposes a public method `squeeze(self, x, axis=None)` that removes axes of unit length from a tensor, mirroring NumPy's `squeeze`. `axis` may be an integer or a sequence of integers selecting which length-1 axes to remove; when `axis` is omitted, all length-1 axes are removed. The NumPy backend (`NumpyBackend` in `src/qibo/backends/numpy.py`) provides this method with the same result as `numpy.squeeze(x, axis=axis)`.
