QPY can't serialize `UCRZGate`
### Environment

- **Qiskit Terra version**: 0.19.2
- **Python version**: 3.9.7
- **Operating system**: macOS Monterey 12.2.1


### What is happening?

While developing a [Grover's tutorial](https://github.com/Qiskit/qiskit-ibm-runtime/pull/236) for the new Qiskit Runtime primitives, I found a bug where the grover circuit submitted to runtime provider with sampler program return `TypeError: __init__() takes 2 positional arguments but 5 were given`. After some investigation, I have narrowed down the issue to `UCRZGate` which is part of the [Grover operator](https://qiskit.org/documentation/stubs/qiskit.circuit.library.GroverOperator.html#qiskit.circuit.library.GroverOperator) in the grover circuit.

```
---------------------------------------------------------------------------
TypeError                                 Traceback (most recent call last)
Input In [1], in <cell line: 20>()
     18 circuit_json = json.loads(json_str)
     19 qpy_file = io.BytesIO(base64.b64decode(circuit_json["circuits"]))
---> 20 circuit = qpy_serialization.load(qpy_file)[0]

File /usr/local/anaconda3/envs/primitives/lib/python3.9/site-packages/qiskit/circuit/qpy_serialization.py:1776, in load(file_obj)
   1774 circuits = []
   1775 for _ in range(file_header[5]):
-> 1776     circuits.append(_read_circuit(file_obj, qpy_version))
   1777 return circuits

File /usr/local/anaconda3/envs/primitives/lib/python3.9/site-packages/qiskit/circuit/qpy_serialization.py:1912, in _read_circuit(file_obj, version)
   1910 custom_instructions = _read_custom_instructions(file_obj, version, vectors)
   1911 for _instruction in range(num_instructions):
-> 1912     _read_instruction(file_obj, circ, out_registers, custom_instructions, version, vectors)
   1913 for vec_name, (vector, initialized_params) in vectors.items():
   1914     if len(initialized_params) != len(vector):

File /usr/local/anaconda3/envs/primitives/lib/python3.9/site-packages/qiskit/circuit/qpy_serialization.py:1121, in _read_instruction(file_obj, circuit, registers, custom_instructions, version, vectors)
   1119         elif gate_name in {"BreakLoopOp", "ContinueLoopOp"}:
   1120             params = [len(qargs), len(cargs)]
-> 1121         gate = gate_class(*params)
   1122     gate.condition = condition_tuple
   1123 if label_size > 0:

TypeError: __init__() takes 2 positional arguments but 5 were given
```

### How can we reproduce the issue?

```python
import io
import json
import base64
from numpy import pi

from qiskit.circuit import qpy_serialization
from qiskit import QuantumCircuit

qc = QuantumCircuit(3)
qc.ucrz([0,0,0,-pi], [1,2], [0])
qc.measure_all()

buf = io.BytesIO()
qpy_serialization.dump(qc, buf)
json_str = json.dumps({
    'circuits': base64.b64encode(buf.getvalue()).decode('utf8')
})
circuit_json = json.loads(json_str)
qpy_file = io.BytesIO(base64.b64decode(circuit_json["circuits"]))
circuit = qpy_serialization.load(qpy_file)[0]
```
qpy code based on [this answer](https://quantumcomputing.stackexchange.com/questions/21795/is-there-a-quantum-circuit-builder-package-that-allows-you-to-import-export-a-ci) by @mtreinish on StackExchange.
### What should happen?

Circuits containing `UCRZGate` should be able to be serialized by QPY.

### Any suggestions?

_No response_
