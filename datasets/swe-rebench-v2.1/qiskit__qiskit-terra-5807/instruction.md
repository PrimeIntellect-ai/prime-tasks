Unable bind parameters in global phase
<!-- ⚠️ If you do not respect this template, your issue will be closed -->
<!-- ⚠️ Make sure to browse the opened and closed issues -->

### Information

- **Qiskit Terra version**: master @ c3b2d7ac
- **Python version**: 3.7.9
- **Operating system**: macOS Big Sur

### What is the current behavior?

If the global phase of a circuit contains a parameter it can currently not be bound:
```python
>>> from qiskit.circuit import QuantumCircuit, Parameter
>>> x = Parameter('x')
>>> circuit = QuantumCircuit(1, global_phase=x)
>>> circuit.bind_parameters({x: 2}).draw()
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/Users/jul/Qiskit/qiskit-terra/qiskit/circuit/quantumcircuit.py", line 1912, in bind_parameters
    return self.assign_parameters(value_dict)
  File "/Users/jul/Qiskit/qiskit-terra/qiskit/circuit/quantumcircuit.py", line 1886, in assign_parameters
    ', '.join(map(str, params_not_in_circuit))))
qiskit.circuit.exceptions.CircuitError: 'Cannot bind parameters (x) not present in the circuit.'
```
The above bug might be due to #5648, since the low-level `_assign_parameter` seems to support global phase binding.

Also, they are not listed when calling `circuit.parameters`:
```python
>>> from qiskit.circuit import QuantumCircuit, Parameter
>>> from qiskit.opflow import StateFn
>>> x = Parameter('x')
>>> circuit = QuantumCircuit(1, global_phase=x)
>>> circuit.parameters
set()
```
