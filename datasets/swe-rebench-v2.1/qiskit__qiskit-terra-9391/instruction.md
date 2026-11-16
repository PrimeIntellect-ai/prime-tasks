QPY fails to serialize `MCXGrayCode` gate
### Environment

- **Qiskit Terra version**: 0.22.4
- **Python version**: 3.9
- **Operating system**: macOS Monterey 12.6


### What is happening?

When you try to serialize a circuit with an `MCXGrayCode` gate using qpy, you get `TypeError: __init__() missing 1 required positional argument: 'num_ctrl_qubits'`. As far as I have seen, other mcx gates do not run into this issue.

I discovered this while trying to run iterative amplitude estimation using the runtime `Sampler`, which relies on `qpy` for serialization.

### How can we reproduce the issue?

```
  from qiskit import QuantumCircuit, qpy
  circuit = QuantumCircuit(11)
  circuit.mcx(list(range(0,9)), 10)
  print('gate name:', circuit.data[0][0].name)

  with open('test.qpy', 'wb') as fd:
      qpy.dump(circuit, fd)

  with open('test.qpy', 'rb') as fd:
      new_qc = qpy.load(fd)[0]
```
This snippet will fail with a similar traceback to:

```
gate name: mcx_gray
  File "/Users/ept/Downloads/ExamplePEO.py", line 131, in <module>
    new_qc = qpy.load(fd)[0]
  File "/Users/ept/Desktop/qgt/qiskit/qpy/interface.py", line 269, in load
    loader(
  File "/Users/ept/Desktop/qgt/qiskit/qpy/binary_io/circuits.py", line 864, in read_circuit
    _read_instruction(file_obj, circ, out_registers, custom_operations, version, vectors)
  File "/Users/ept/Desktop/qgt/qiskit/qpy/binary_io/circuits.py", line 258, in _read_instruction
    gate = gate_class(*params)
TypeError: __init__() missing 1 required positional argument: 'num_ctrl_qubits'
```

### What should happen?

It should not have failed.

### Any suggestions?

[HIDDEN]

I'm happy to open a bugfix PR, but because I'm not that familiar with qpy, I wanted to document the problem in this issue first.
