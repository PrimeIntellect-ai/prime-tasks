measure_all() function on PyQuil programs
Alternative to having to do:
```
for qubit in program.get_qubits():
    program.measure(qubit, qubit)
```
