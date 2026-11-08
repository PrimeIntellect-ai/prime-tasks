Tensorflow einsum error when measuring density matrices
**Describe the bug**
Measuring density matrices with more than 6 qubits using any Tensorflow backend leads to an einsum error. Thanks @AdrianPerezSalinas for finding this.

**To Reproduce**
```Python
from qibo import models, gates

circuit = models.Circuit(7, density_matrix=True)
circuit.add(gates.M(*range(7)))
result = circuit(nshots=100)
```
gives

```
tensorflow.python.framework.errors_impl.UnimplementedError: Unsupported rank: 7 while handling repeated indices. Up to rank 6 is supported. [Op:Einsum]
```

**Additional context**
Einsum is used here to calculate the probability distribution from the density matrix, [by tracing out unmeasured qubits](https://github.com/Quantum-TII/qibo/blob/0422b84a189ff86dd6a900b76bd76cac90735d72/src/qibo/core/states.py#L149). Numpy backends do not have this issue.
