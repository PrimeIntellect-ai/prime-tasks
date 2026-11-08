VF2Layout transpiler pass inserts extra qubits (more than are in the device)
### Environment

- **Qiskit Terra version**: 0.21.2
- **Python version**: 3.10.5
- **Operating system**: Linux

Here are more qiskit related versions:

qiskit-ibm-runtime==0.6.2
qiskit-ibmq-provider==0.19.2



### What is happening?

When using `ibmq_guadalupe` as a backend (num_qubits == 16), I see that for a circuit with 16 qubits initially that after transpile num_qubits is more than 16.

### How can we reproduce the issue?

The following code produces the problem for me:

```python
qasm_str = """
OPENQASM 2.0;
include "qelib1.inc";
qreg q[16];
creg c[5];
rz(pi/2) q[0];
sx q[0];
sx q[1];
rz(-pi/4) q[1];
sx q[1];
rz(pi/2) q[1];
rz(2.8272143) q[0];
rz(0.43324854) q[1];
sx q[1];
rz(-0.95531662) q[7];
sx q[7];
rz(3*pi/4) q[7];
barrier q[1],q[10],q[4],q[0],q[7];
measure q[1] -> c[0];
measure q[10] -> c[1];
measure q[7] -> c[2];
measure q[4] -> c[3];
measure q[0] -> c[4];
"""

from qiskit import QuantumCircuit, transpile
from qiskit_ibm_runtime import Sampler

from qiskit_ibm_runtime import QiskitRuntimeService


service = QiskitRuntimeService(channel="ibm_quantum")
backend = service.backend("ibmq_guadalupe")

circ = QuantumCircuit.from_qasm_str(qasm_str)

best_circ = transpile(
    circ,
    backend=backend,
    scheduling_method="alap",
    optimization_level=3,
    approximation_degree=0,
)

print(circ.num_qubits)
print(best_circ.num_qubits)
```

This prints 16 and then 20.

Ideally, the next code here would be

```python
with Sampler(circuits=circ_list, service=service, options={"backend": "ibmq_guadalupe"}) as sampler:
    result_c = sampler(circ_list, shots=shots)
```

but that produces an error string which includes `TranspilerError: 'Number of qubits (20) in circuit-78 is greater than maximum (16) in the coupling_map`.

### What should happen?

The transpiled circuit should have a number of qubits consistent with the backend and it should be able to run the circuit on the backend.

### Any suggestions?

The behavior seems similar to https://github.com/Qiskit/qiskit-terra/issues/7677. I tried doing the transpile with both the backend object from qiskit_ibm_runtime (so BackendV2) and from qiskit-ibmq-provider (so BackendV1) but got the same result. I checked that `len(backend.properties().qubits)` was also 16 for the BackendV1 case.

[HIDDEN]

If I tweak the example circuit so that it includes a gate on every qubit 0-15, then the transpile produces a circuit with 16 qubits as expected.

### Additional contract requirements

When this 16-qubit circuit is laid out for the 16-qubit backend, the resulting circuit must remain within the backend’s 16-qubit capacity so it can be submitted to that backend.
