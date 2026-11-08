Cannot compose circuits with different numbers of measurements
<!-- ⚠️ If you do not respect this template, your issue will be closed -->
<!-- ⚠️ Make sure to browse the opened and closed issues -->

### Information

- **Qiskit Terra version**: 0.17.4
- **Python version**:
- **Operating system**:

### What is the current behavior?
Compose fails when combining circuits with no measurements together with those that do, e.g.

```python
ansatz = TwoLocal(2, rotation_blocks='ry',
                  entanglement_blocks='cx')

qc = QuantumCircuit(2)
qc.measure_all()

ansatz.compose(qc)
```

gives:

CircuitError: "Trying to compose with another QuantumCircuit which has more 'in' edges."

while `+` works, but is deprecated in favor of `compose`.



### Steps to reproduce the problem



### What is the expected behavior?



### Suggested solutions

### Additional contract requirements

When a circuit with classical bits is composed onto one that has none, the resulting circuit must retain the operand's operations, including its measurements. Each retained measurement must target a classical bit in the resulting circuit. The operand's classical registers do not need to be represented as the same register objects in the result.
