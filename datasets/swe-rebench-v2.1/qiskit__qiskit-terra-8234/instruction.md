Qasm exporter fails with `CXGate` and `CU1Gate` generates an empty unitary: `QasmError: "Expected an ID, received '{'"`
### Environment

- **Qiskit Terra version**: 0.19.1
- **Python version**: 3.8
- **Operating system**: Ubuntu 18.04.6 LTS


### What is happening?

The qasm exporter creates a unitary gate with empty definition.

### How can we reproduce the issue?

Run the code:
```python
import qiskit
from qiskit import QuantumCircuit, ClassicalRegister, QuantumRegister
from qiskit.circuit.library.standard_gates import *
from qiskit import transpile

qr = QuantumRegister(3, name='qr') # with 2 bits it doesn't crash
cr = ClassicalRegister(3, name='cr')
qc = QuantumCircuit(qr, cr, name='qc')
subcircuit = QuantumCircuit(qr, name='subcircuit')

subcircuit.append(CXGate(), qargs=[qr[0], qr[1]], cargs=[])
subcircuit.append(CU1Gate(3), qargs=[qr[0], qr[1]], cargs=[])
qc.append(subcircuit, qargs=qr)
qc.append(subcircuit.inverse(), qargs=qr)
qc.measure(qr, cr)
qc = transpile(qc, optimization_level=3)

my_qasm = qc.qasm()
print(my_qasm)
```
Output:
```
OPENQASM 2.0;
include "qelib1.inc";
gate unitary139827973619136  {
}
qreg qr[3];
creg cr[3];
unitary139827973619136 qr[0],qr[1];
measure qr[0] -> cr[0];
measure qr[1] -> cr[1];
measure qr[2] -> cr[2];
```

Run this code to read back the exported qasm:
```python
qc = QuantumCircuit.from_qasm_str(my_qasm)
```
But it gives an error because the qasm is incorrect, since it has gate unitary139827973619136 which is empty. Output:
```
Error near line 3 Column 3
....
QasmError: "Expected an ID, received '{'"
```


### What should happen?

The generated qasm should include the definition of the gate. This works if the optimization level is lower or if we set the registers to use 2 bits. This is odd, since the correctness of the exported qasm should not depend on the size of the circuit or on the optimization level.

### Any suggestions?

It must be connected to the optimizations running on optimization level 3 and it must depend also on the size of the registers. It could be curious to see, maybe in the test suite there was a test case testing a similar case but with a smaller size of register and it passed there, whereas with 3 or more bits as size of the registers it fails. This is just speculation.
Looking forward to your feedback, thanks in advance.

### Additional contract requirements

- The exported OpenQASM 2 must define the unitary as a `gate` with one qubit
  parameter per qubit of the unitary.
- The exported OpenQASM 2 must be readable again by
  `QuantumCircuit.from_qasm_str`.
