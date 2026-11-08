NumpyGenericOperator lincomb apply_inverse infinite recursion in 0.5.x
The following raises `RecursionError` on 0.5.x.
```python
import numpy as np
from pymor.operators.numpy import NumpyMatrixOperator, NumpyGenericOperator

n = 2
I1 = NumpyMatrixOperator(np.eye(n))
I2 = NumpyGenericOperator(lambda x: x, dim_source=n, dim_range=n)
v = I1.source.from_numpy(np.ones(n))

(I1 + I2).apply_inverse(v)
```

On master, `jacobian` method raises `NotImplementedError`.

Should the recursion error be fixed in 0.5.x?

### Additional contract requirements

For the displayed sum, `apply_inverse` must not fail because of infinite recursion or raise `RecursionError`. If it returns a value, it must be the inverse of the sum (for the shown input, `0.5 * v`); if inversion cannot be performed, it may report an appropriate exception instead.
