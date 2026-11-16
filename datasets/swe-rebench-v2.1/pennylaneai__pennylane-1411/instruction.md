Copying `qml.ControlledQubitUnitary`
The `Operator` base class defines a `__copy__` method for operators.  For almost all `Operator`'s, this method works fine to duplicate a given instance.

But `qml.ControlledQubitUnitary` has a more complicated set of data, and copying it does not work fully.

```python
import pennylane as qml
from pennylane import numpy as np

import copy

op = qml.ControlledQubitUnitary(np.eye(2) * 1j, wires=[0], control_wires=[2])
print(op.matrix)

cop = copy.copy(op) # = op.__copy__()
print(cop.matrix)
```

Error
```
---------------------------------------------------------------------------
AttributeError                            Traceback (most recent call last)
<ipython-input-6-4a2b6ba0ebcf> in <module>
----> 1 cop.matrix

pennylane/pennylane/operation.py in matrix(self)
    666     @property
    667     def matrix(self):
--> 668         op_matrix = self._matrix(*self.parameters)
    669
    670         if self.inverse:

pennylane/pennylane/ops/qubit.py in _matrix(self, *params)
   2203
   2204     def _matrix(self, *params):
-> 2205         if self._CU is None:
   2206             self._CU = block_diag(np.eye(self._padding_left), self.U, np.eye(self._padding_right))
   2207
```

[HIDDEN]

We should also test `op.__copy__()` for each operation type.  Note that just calling `__copy__()` is not sufficient to tell if there is a problem.  In this situation, you need to call methods like `op_copy.matrix` to see that the copy was insufficient.

Relevant locations in code:
* [``ControlledQubitUnitary``](https://github.com/PennyLaneAI/pennylane/blob/0dcbed53b470eb7f6f93b54077e36ca6287235cf/pennylane/ops/qubit.py#L2110)
* [``Operator.__copy__(self)``](https://github.com/PennyLaneAI/pennylane/blob/0dcbed53b470eb7f6f93b54077e36ca6287235cf/pennylane/operation.py#L255)

### Additional contract requirements

- Copying an operator with `copy.copy(op)` or `op.__copy__()` must produce a usable copy whose matrix matches the original, including for `qml.ControlledQubitUnitary`.
