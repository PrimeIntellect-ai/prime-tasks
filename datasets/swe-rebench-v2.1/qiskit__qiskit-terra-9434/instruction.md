`PauliOp.adjoint()` does not return correct value
### Environment

- **Qiskit Terra version**: 0.24.0.dev0+e981b7e
- **Python version**: 3.8.16
- **Operating system**: Linux


### What is happening?

`PauliOp.adjoint()` does not return a correct answer like `SparsePauliOp.adjoint()` does.

### How can we reproduce the issue?

```python
from qiskit.opflow.primitive_ops import PauliOp
from qiskit.quantum_info import Pauli, SparsePauliOp

sparse_pauli_op = SparsePauliOp(["iX"], [3.0])
expected = SparsePauliOp(["-iX"], [3.0])
assert sparse_pauli_op.adjoint() == expected # this is OK

pauli_op = PauliOp(Pauli("X"), coeff=3j)
expected = PauliOp(Pauli("X"), coeff=-3j)
assert pauli_op.adjoint() == expected # this is also OK

pauli_op = PauliOp(Pauli("iX"), coeff=3)
expected = PauliOp(Pauli("-iX"), coeff=3)
assert pauli_op.adjoint() == expected # returns AssertionError
```

### What should happen?

The code above should not return `AssertionError`.

### Any suggestions?

_No response_
