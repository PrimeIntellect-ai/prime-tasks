DiagonalGate does not raise when diagonal entries do not have modulus 1
<!-- ⚠️ If you do not respect this template, your issue will be closed -->
<!-- ⚠️ Make sure to browse the opened and closed issues -->

### Information

- **Qiskit Terra version**: 0.12.0
- **Python version**: 3.6.9
- **Operating system**: Linux

### What is the current behavior?

`diag_gate` allows entries whose modulus are not one.

### Steps to reproduce the problem

```
import qiskit
from numpy import exp,pi

backend = qiskit.Aer.get_backend("statevector_simulator")
qc = qiskit.QuantumCircuit(1)
qc.h(0)
qc.diag_gate([exp(1j*pi/8),0],qc.qregs)  # <-- no error here
qiskit.execute(qc,backend).result().to_dict()
```

### What is the expected behavior?

An error should be raised.

### Suggested solutions
[HIDDEN]
