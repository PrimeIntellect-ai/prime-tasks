Loading Qpy file with initialized quantum circuit throws "QiskitError: 'Sum of amplitudes-squared is not 1, but 0.0.'"
### Environment

- **Qiskit Terra version**: 0.25.1
- **Python version**:  3.10.1


### What is happening?

When trying to load a Qpy file that was made from a circuit with an initialize instruction, it produces the following error:
```
Traceback (most recent call last):
  Cell In[22], line 13
    qc = qpy.load(fd)[0]
  File /opt/conda/lib/python3.10/site-packages/qiskit/qpy/interface.py:269 in load
    loader(
  File /opt/conda/lib/python3.10/site-packages/qiskit/qpy/binary_io/circuits.py:1092 in read_circuit
    _read_instruction(file_obj, circ, out_registers, custom_operations, version, vectors)
  File /opt/conda/lib/python3.10/site-packages/qiskit/qpy/binary_io/circuits.py:301 in _read_instruction
    gate = gate_class(params)
  File /opt/conda/lib/python3.10/site-packages/qiskit/extensions/quantum_initializer/initializer.py:58 in __init__
    self._stateprep = StatePreparation(params, num_qubits, normalize=normalize)
  File /opt/conda/lib/python3.10/site-packages/qiskit/circuit/library/data_preparation/state_preparation.py:107 in __init__
    raise QiskitError(f"Sum of amplitudes-squared is not 1, but {norm}.")
QiskitError: 'Sum of amplitudes-squared is not 1, but 0.0.'
```

### How can we reproduce the issue?

Run the following:
```python
import qiskit
from qiskit import QuantumCircuit, ClassicalRegister, QuantumRegister
from qiskit import qpy

qr = QuantumRegister(8, name='qr')
cr = ClassicalRegister(8, name='cr')
qc = QuantumCircuit(qr, cr, name='qc')
qc.initialize(0, qc.qubits)

with open('tmp.qpy', 'wb') as fd:
    qpy.dump(qc, fd)
with open('tmp.qpy', 'rb') as fd:
    qc = qpy.load(fd)[0]
```

### What should happen?

Qpy should be able to load the circuit from the file generated.

### Any suggestions?

_No response_
