QuantumCircuit `.clear()` and `.copy_empty_like()` functionality
### What should we add?

Sometimes it can be useful to erase all instructions in a QuantumCircuit. This request is for:
1. [Clear functionality](https://github.com/pedrorrivero/qiskit-terra/blob/794db4792e97adca4a78eb4f3411c04e50665df7/qiskit/circuit/quantumcircuit.py#L2311-L2313) to erase all instructions from a QuantumCircuit → `.clear()`.
We not only need to clear all data, but (at least) also update the parameter table:
```python
[HIDDEN]
```
2. [Copy empty functionality](https://github.com/Qiskit/qiskit-terra/blob/main/qiskit/dagcircuit/dagcircuit.py#L511-L538) to get a cleared copy of a QuantumCircuit → `.copy_empty_like()`.
This functionality is already implemented for DAGCircuit, and should retain all relevant circuit properties other than the instructions and associated parameters (e.g. registers, bits, name, metadata). Notice that `quantum_circuit.copy().clear()` would give the desired outcome, however `.copy()` performs a deepcopy of the circuit, which we would then erase almost completely when deleting the instructions, so this method should provide a more efficient way to do this.


TODO:
- [ ] `.clear()`
- [ ] `.copy_empty_like()`

### Additional contract requirements

- `QuantumCircuit.clear()` removes all instructions and all parameters from the circuit, leaving its registers, metadata, calibrations, global phase and name unchanged.
- `QuantumCircuit.copy_empty_like(name: Optional[str] = None) -> QuantumCircuit` returns a new circuit that contains no instructions and no parameters, while preserving the original circuit's registers, global phase, metadata and calibrations. When `name` is given, the returned circuit uses that name; otherwise it keeps the original name.
- `QuantumCircuit.copy_empty_like()` must not copy the original circuit's instruction data.
