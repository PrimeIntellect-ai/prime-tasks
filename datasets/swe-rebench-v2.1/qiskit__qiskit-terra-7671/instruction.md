Submitting a non-string label to instructions leads to a TypeError when a QuantumCircuit instance is drawn.
### Environment

- **Qiskit Terra version**: 0.19.2
- **Python version**: 3.8.8
- **Operating system**: Pop!_OS 21.10


### What is happening?

While applying an `X` gate to two qubits, I made a mistake in which instead of passing in the target qubit indices as a list like so, `qc.x([0, 1])`, I submitted them as separate parameters as in,  `qc.x(0, 1)`. This lead to the following exception when I later called `qc.draw`:

```
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/username/anaconda3/lib/python3.8/site-packages/qiskit/visualization/text.py", line 657, in __repr__
    return self.single_string()
  File "/home/username/anaconda3/lib/python3.8/site-packages/qiskit/visualization/text.py", line 665, in single_string
    return "\n".join(self.lines()).encode(self.encoding).decode(self.encoding)
  File "/home/username/anaconda3/lib/python3.8/site-packages/qiskit/visualization/text.py", line 709, in lines
    layers = self.build_layers()
  File "/home/username/anaconda3/lib/python3.8/site-packages/qiskit/visualization/text.py", line 1138, in build_layers
    layer, current_connections, connection_label = self._node_to_gate(node, layer)
  File "/home/username/anaconda3/lib/python3.8/site-packages/qiskit/visualization/text.py", line 1005, in _node_to_gate
    gate_text = gate_text + params
TypeError: unsupported operand type(s) for +: 'int' and 'str'
```
I quickly realized that I had failed to pass in the indices as a list, but was puzzled as to why I was getting this exception. I took a look at the [documentation](https://qiskit.org/documentation/stubs/qiskit.circuit.QuantumCircuit.x.html?highlight=x#qiskit.circuit.QuantumCircuit.x) corresponding to `x` and saw that the second index had been stored in the optional `label` parameter. This results in a `TypeError` being raised [here](https://github.com/Qiskit/qiskit-terra/blob/1ae663d80295dce1b6ff25cbf29c640bf2ff9952/qiskit/visualization/text.py#L1055) when the instruction is processed during a draw.

Note that a similar error arises, when one attempts to draw the circuit using Matplotlib, so this is not isolated to text based circuit displays:
```
Traceback (most recent call last):
  File "error.py", line 6, in <module>
    qc.draw(output='mpl')
  File "/home/username/anaconda3/lib/python3.8/site-packages/qiskit/circuit/quantumcircuit.py", line 1865, in draw
    return circuit_drawer(
  File "/home/username/anaconda3/lib/python3.8/site-packages/qiskit/visualization/circuit_visualization.py", line 284, in circuit_drawer
    image = _matplotlib_circuit_drawer(
  File "/home/username/anaconda3/lib/python3.8/site-packages/qiskit/visualization/circuit_visualization.py", line 678, in _matplotlib_circuit_drawer
    return qcd.draw(filename)
  File "/home/username/anaconda3/lib/python3.8/site-packages/qiskit/visualization/matplotlib.py", line 278, in draw
    self._get_layer_widths()
  File "/home/username/anaconda3/lib/python3.8/site-packages/qiskit/visualization/matplotlib.py", line 394, in _get_layer_widths
    and len(gate_text) < 3
TypeError: object of type 'int' has no len()
```

### How can we reproduce the issue?

This issue can be produced by executing the following code:
```
from qiskit import QuantumCircuit

qc = QuantumCircuit(2)
qc.x(0, 1)
print(qc)
```
Note that here I use a `print` instead of a `draw` to demonstrate that the same code is touched on either path.

### What should happen?

As a Qiskit user, I would expect an exception to be raised when I attempt to create an instruction while providing a label with an invalid type, rather than when I try to draw it. Currently, I receive an exception, but it's distanced from the root cause and isn't as clear or clean as a `ValueError` raised on instruction creation would be.

### Any suggestions?

I'm new to Qiskit, so forgive me if my suggestions are off base, but I did some sleuthing and determined a possible fix. Looking through the code, I found that all instructions have [Instruction](https://github.com/Qiskit/qiskit-terra/blob/1ae663d80295dce1b6ff25cbf29c640bf2ff9952/qiskit/circuit/instruction.py#L50) as their base class. [HIDDEN] I have a draft of such a fix working locally and would love to submit a pull request, if the group would like to assign this issue to me. Even if we don't go with my suggested fix, my willingness to help out remains.

### Additional contract requirements

- An instruction's optional `label` may be a string or `None`.
- Creating an instruction with a `label` that is neither a string nor `None` raises `TypeError` at instruction creation time.
- Assigning a value that is neither a string nor `None` to an instruction's `label` raises `TypeError`.
- The required exception for an invalid label is `TypeError`, not `ValueError`.
