the .on_qubits() feature fails when the quantum circuit has .controlled_by() gates.
**Describe the bug**
When trying to add a `Circuit` with `.controlled_by()` gates into a bigger circuit with the `.on_qubits()` method, an error occurs.

**To Reproduce**
```Python
circ1 = Circuit(1)
circ1.add(gates.H(0))

circ2 = Circuit(2)
circ2.add(gates.CNOT(0,1))
circ2.add(gates.H(1).controlled_by(0))

circ3 = Circuit(2)
circ3.add(circ1.on_qubits(*[0]))
circ3.add(circ2.on_qubits(*range(2)))
```

Seems to only happens when `controlled_by` gates are applied, as the CNOT gate seems to go though fine when doing:

```Python
for gate in circ2.on_qubits(*range(2)):
      print(gate)
```
