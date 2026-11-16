Add `qubits` and `clbits` arguments to QuantumCircuit.from_instructions
### What should we add?

These arguments can be used to initialize the QuantumCircuit. That way the user can control the ordering of `circuit.qubits`; otherwise, they will be in the order that the qubits are added.

### Additional contract requirements

- `QuantumCircuit.from_instructions(instructions, *, qubits=(), clbits=(), name=None, global_phase=0, metadata=None)` accepts optional `qubits` and `clbits` iterables.
- All supplied qubits and clbits are added to the resulting circuit before the instructions are processed, including any supplied bit that does not appear in any instruction.
- The order of the supplied `qubits` and `clbits` determines the ordering of the resulting `circuit.qubits` and `circuit.clbits`.
- When `qubits` or `clbits` are omitted, the corresponding circuit ordering follows the order in which those bits first appear in the instruction stream.
