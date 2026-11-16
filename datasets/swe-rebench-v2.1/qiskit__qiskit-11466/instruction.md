Displaying control-annotated operations
### Environment

- **Qiskit Terra version**: development
- **Python version**: 3.10
- **Operating system**: windows


### What is happening?

#11202 added drawer support to annotated operations.

However, for a gate with 2 or more qubits, its controlled-annotated version is not displayed correctly: the box for the controlled gate does not include all of its qubits. The code snippet in the next session draws a control-annotated CX-gate with 1 control qubit, leading to:

```
q_0: ──■───
     ┌─┴──┐
q_1: ┤ Cx ├
     └────┘
q_2: ──────
```
The box for the CX-gate should include both `q_1` and `q_2`.


### How can we reproduce the issue?

```
from qiskit.circuit import QuantumCircuit
from qiskit.circuit.annotated_operation import AnnotatedOperation, InverseModifier, ControlModifier
from qiskit.circuit.library import CXGate

gate = AnnotatedOperation(CXGate(), ControlModifier(1))
circuit = QuantumCircuit(gate.num_qubits)
circuit.append(gate, range(gate.num_qubits))
print(circuit)
```

### What should happen?

As explained above, the box for the controlled gate should include all of its qubits (namely, `q_1` and `q_2`).

### Any suggestions?

_No response_
