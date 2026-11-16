QPY fails to deserialize some `ControlledGate`s
### Environment

- **Qiskit Terra version**: 0.20.1
- **Python version**: 3.8.12
- **Operating system**: Ubuntu 20.04.4


### What is happening?

QPY successfully serializes circuits containing instances of `ControlledGate`, but deserialization fails when `ControlledGate.__init__(...)` is called in `_read_instruction` with e.g.:
```
File "<..>/qiskit/qpy/binary_io/circuits.py", line 250, in _read_instruction
    gate = gate_class(*params)

TypeError: __init__() missing 3 required positional arguments: 'name', 'num_qubits', and 'params'
```

### How can we reproduce the issue?

```
from io import BytesIO
from qiskit import qpy, QuantumCircuit
from qiskit.circuit.library import DCXGate

controlled_gate = DCXGate().control(1)  # create instance of ControlledGate

circuit = QuantumCircuit(3)
circuit.append(controlled_gate, [0, 1, 2])

buf = BytesIO()
qpy.dump(circuit, buf)  # ok
qpy.load(BytesIO(buf.getbuffer()))  # TypeError: __init__() missing 3 required positional arguments: 'name',          'num_qubits', and 'params'
```

### What should happen?

`qpy.load()` should succeed

### Any suggestions?

_No response_

### Additional contract requirements

- A circuit containing a controlled gate created with `Gate.control()` (such as `DCXGate().control(1)`, or a custom gate with its own definition controlled by two qubits) must round-trip through QPY: `qpy.load()` returns a circuit whose decomposition matches the original circuit's decomposition.
