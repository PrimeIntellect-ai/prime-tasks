`XXPlusYYGate.to_matrix()` fails after qasm2 roundtrip
### Environment

- **Qiskit version**: 1.0.2
- **Python version**: 3.11.0
- **Operating system**: Linux


### What is happening?

After a qasm2 round-trip, a `XXPlusYYGate`'s `to_matrix()` method no longer works.

~~This problem seems somewhat special to `XXPlusYYGate`; it does not exist for most other two-qubit gates we have tried.~~

I've been able to reproduce this problem as well for `CSGate`, but not `CXGate` or `CZGate`.

### How can we reproduce the issue?

```python
from qiskit import qasm2, QuantumCircuit
from qiskit.circuit.library import XXPlusYYGate

# Build a circuit with a single XXPlusYYGate
qc = QuantumCircuit(2)
qc.append(XXPlusYYGate(0.1), [0, 1])

# Perform a qasm2 round trip
program = qasm2.dumps(qc)
qc2 = QuantumCircuit.from_qasm_str(program)

# Call to_matrix on original circuit instructions (works)
for inst in qc.data:
    inst.operation.to_matrix()

# Call to_matrix on circuit instructions after serialization (fails)
for inst in qc2.data:
    inst.operation.to_matrix()
```

throws the exception

```
File ~/serverless/.direnv/python-3.11.0/lib/python3.11/site-packages/qiskit/circuit/gate.py:63, in Gate.to_matrix(self)
     61 if hasattr(self, "__array__"):
     62     return self.__array__(dtype=complex)
---> 63 raise CircuitError(f"to_matrix not defined for this {type(self)}")

CircuitError: "to_matrix not defined for this <class 'qiskit.qasm2.parse._DefinedGate'>"
```

### What should happen?

it should work the same as the circuit that did not undergo a round trip.

### Any suggestions?

_No response_
