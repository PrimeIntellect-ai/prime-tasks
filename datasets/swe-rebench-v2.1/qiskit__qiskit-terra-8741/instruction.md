Drawing a circuit with idle_wires=False causes the circuit to break in future draw/qpy events
### Environment

- **Qiskit Terra version**: main
- **Python version**: 3.9.1
- **Operating system**: OSX


### What is happening?

When drawing a circuit with `circuit.draw(idle_wires=False)` the circuit is somehow mutated to fail on future drawing or qpy serialization events.



### How can we reproduce the issue?

Using the circuit below. Message for QPY file.

```python
from qiskit import qpy

with open('test.qpy', 'wb') as fd:
    qpy.dump(transpiled_bit_code_circuit, fd)

with open('test.qpy', 'rb') as fd:
    new_qc = qpy.load(fd)[0]

new_qc.draw(idle_wires=False)
new_qc.draw(idle_wires=False)
```



### What should happen?

Circuit should draw twice.

### Any suggestions?

_No response_

### Additional contract requirements

- After drawing a circuit with `idle_wires=False`, callers must still be able to draw it again and serialize and deserialize it using QPY.
