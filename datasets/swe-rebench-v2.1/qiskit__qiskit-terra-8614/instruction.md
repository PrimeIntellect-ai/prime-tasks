Wrong decomposition rule when decomposing into a single-qubit instruction
### Environment

- **Qiskit Terra version**: 0.21.1
- **Python version**: 3.9.13
- **Operating system**: macOS Monterey


### What is happening?

I use placeholder instructions with one or more qubits and clbits to create circuits in different configurations.
The placeholders are created with the maximum amount of qubits and clbits needed, which might be more than needed for some specific configurations.

However, if I put *one single-qubit instruction* into a placeholder with 1 qubit and *C* clbits, `circuit.decompose()` fails with
```
qiskit.dagcircuit.exceptions.DAGCircuitError:
'Cannot replace node of width (1 qubits, C clbits) with instruction of mismatched width (1 qubits, 0 clbits).'
```

### How can we reproduce the issue?

```python
from qiskit import QuantumCircuit

placeholder = QuantumCircuit(1, 1)
placeholder.h(0)
# placeholder.x(0) # uncomment this line to make the example work

pld_instr = placeholder.to_instruction()

circuit = QuantumCircuit(3, 3)
circuit.h(0)
circuit.append(placeholder, [0], [0])
circuit.x(1)

print(circuit)
print(circuit.decompose()) # FAILS

```

### What should happen?

The decomposition pass should not fail, and behave the same as if multiple instructions would have been put into the placeholder. (See example when uncomment line 5)


### Any suggestions?

As far as I see it, the problem arises because of [HIDDEN] in the decomposition pass:

[HIDDEN]

This maybe seems to be a optimization (?) that can quickly handle a single-qubit instruction. However, I think it does not handle the case when the instruction does not have the same amount of clbits as the placeholder.


[HIDDEN]
