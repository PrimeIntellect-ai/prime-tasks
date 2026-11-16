Parameterized circuits yield incorrect QASM output
<!-- ⚠️ If you do not respect this template, your issue will be closed -->
<!-- ⚠️ Make sure to browse the opened and closed issues -->

### Information

- **Qiskit Terra version**: master
- **Python version**:
- **Operating system**:

### What is the current behavior?
For example:
```python

from qiskit import *
from qiskit.circuit import Parameter

alpha = Parameter('alpha')
qc = QuantumCircuit(1)
qc.p(alpha, 0)
qc.qasm(True)
```
gives

```
OPENQASM 2.0;
include "qelib1.inc";
qreg q[1];
p(alpha) q[0];
```
but alpha is not defined.  This leads to errors when importing the QASM.
### Steps to reproduce the problem



### What is the expected behavior?



### Suggested solutions
I am guessing that this is a QASM2 issue that is to be fixed in QASM3.  However there is no exception raised here to indicate that the QASM is invalid for a parameterized circuit.

### Additional contract requirements

- `QuantumCircuit.qasm` has the signature `qasm(self, formatted=False, filename=None)`.
- For a circuit with no free parameters, `qasm` returns the OpenQASM 2.0 representation as a string.
- For a circuit with free (unbound) parameters, `qasm` raises `QasmError` (from `qiskit.qasm.exceptions`) instead of returning OpenQASM 2.0 that references undefined parameters.
