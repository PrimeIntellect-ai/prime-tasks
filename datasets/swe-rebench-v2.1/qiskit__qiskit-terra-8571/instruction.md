qpy changes names of `ControlledGate`s with non-default `ctrl_state`
### Environment

- **Qiskit Terra version**: 0.22.1
- **Python version**: 3.8
- **Operating system**: Ubuntu 22.04.1


### What is happening?

qpy appends an extra `"_o{ctrl_state}"` to the name of `qiskit.circuit.ControlledGate` instances with non-default values for `ctrl_state` (so after one serialization+deserialization round the `gate.name` becomes `"{name}_o{ctrl_state}_o{ctrl_state}"`, and after a second round becomes `"{name}_o{ctrl_state}_o{ctrl_state}_o{ctrl_state}"`, etc)

### How can we reproduce the issue?

```
import qiskit
import qiskit.qpy
import io

gate = qiskit.circuit.library.SGate().control(1, ctrl_state="0")  # create an instance of ControlledGate
print(gate.name)  # prints "cs_o0"

circuit = qiskit.circuit.QuantumCircuit(2)
circuit.append(gate, [0, 1])
print(circuit[0].operation.name)  # prints "cs_o0"

qiskit.qpy.dump(circuit, buf := io.BytesIO())
circuit = qiskit.qpy.load(io.BytesIO(buf.getbuffer()))[0]
print(circuit[0].operation.name)  # prints "cs_o0_o0"

qiskit.qpy.dump(circuit, buf := io.BytesIO())
circuit = qiskit.qpy.load(io.BytesIO(buf.getbuffer()))[0]
print(circuit[0].operation.name)  # prints "cs_o0_o0_o0"
```

### What should happen?

every `print` statement above should print `"cs_o0"`

### Any suggestions?

_No response_
