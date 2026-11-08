Add a new QuantumCircuit constructor QuantumCircuit.from_instructions
### What should we add?

Creating a QuantumCircuit and appending operations into it is a very common pattern. It would be very convenient to be able to create a QuantumCircuit by directly passing an iterator of operations, something like:
```python
@staticmethod
def from_ops(ops: Iterator[tuple[Instruction, Sequence[Qubit], Sequence[Clbit]]]) -> QuantumCircuit:
    circuit = QuantumCircuit()
[HIDDEN]
    return circuit
```
Currently this is not possible as written but it would be if my proposal https://github.com/Qiskit/qiskit-terra/issues/8707 were implemented.
