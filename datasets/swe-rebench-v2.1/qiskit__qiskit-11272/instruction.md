Barrier instruction ignores number of qubits when passed qubit operands as set
### Environment

- **Qiskit Terra version**: 0.45
- **Python version**: 3.9.*
- **Operating system**: Linux



### What is happening?

When a circuit is created with integer qubit operands and a barrier is applied with those operands as a set the barrier instruction is created for a single qubit operand.

### How can we reproduce the issue?

```python
from qiskit import QuantumCircuit
qc = QuantumCircuit(2)
qc.barrier({0, 1})
print(qc.data)
```
gives
```
>>> [CircuitInstruction(operation=Instruction(name='barrier', num_qubits=1, num_clbits=0, params=[]), qubits=(Qubit(QuantumRegister(2, 'q'), 0), Qubit(QuantumRegister(2, 'q'), 1)), clbits=())]
```

### What should happen?

I would expect (and the behaviour was this way in 0.44)

```
>>> [CircuitInstruction(operation=Instruction(name='barrier', num_qubits=2, num_clbits=0, params=[]), qubits=(Qubit(QuantumRegister(2, 'q'), 0), Qubit(QuantumRegister(2, 'q'), 1)), clbits=())]
```

Passing a list gives the expected behaviour
```python
qc.barrier([0, 1])
```
### Any suggestions?

_No response_
