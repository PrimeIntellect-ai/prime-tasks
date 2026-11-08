Truncating floats in QASM dump alters circuit's functionality
### Information

- **Qiskit Terra version**: 0.18.3 (dates back to 0.14)
- **Python version**: Any
- **Operating system**: Any

### What is the current behavior?
In #4276, the `pi_check` function was introduced for pretty printing the list of parameters when dumping a `QuantumCircuit` to `qasm`, see
https://github.com/Qiskit/qiskit-terra/blob/637acc0c408d8199dd58780cc3dafabc14e61a0f/qiskit/circuit/instruction.py#L450-L463
[HIDDEN] This leads to the following situation:

Let's say I have a circuit that contains, e.g., a phase gate with more than 8 significant digits in its rotation angle.
Then, I dump the circuit to a `.qasm` file and read that file back into a `QuantumCircuit`.
If I compare both unitary functionalities (i.e., the respective unitary matrices), these will no longer be equal due to the numerical error introduced by the truncation.

### Steps to reproduce the problem

```python
from qiskit import QuantumCircuit, execute, Aer

qc = QuantumCircuit(1)
qc.p(1/4096, 0)

qasm_str = qc.qasm()

backend = Aer.get_backend('aer_simulator')

qc.save_unitary()
job = execute(qc, backend)
result = job.result()
unitary = result.get_unitary(qc)

qc_qasm = QuantumCircuit.from_qasm_str(qasm_str)
qc_qasm.save_unitary()
job = execute(qc_qasm, backend)
result = job.result()
unitary_qasm = result.get_unitary(qc_qasm)

print(unitary == unitary_qasm)
```
yields
```bash
[[ True  True]
 [ True False]]
```

### What is the expected behavior?

Merely dumping a file to `.qasm` should not alter a circuit's functionality.

### Suggested solutions

[HIDDEN]
