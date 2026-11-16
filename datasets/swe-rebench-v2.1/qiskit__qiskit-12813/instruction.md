2Q gate synthesis with fractional gates
### Environment

- **Qiskit version**: main
- **Python version**: doesn't matter
- **Operating system**: doesn't matter


### What is happening?

When I build a Qiskit `Target` that supports two qubit basis gates with arbitrary rotation angle, it cannot transpile the circuit if the added basis gate is other than `RZXGate` or `RXXGate`.

### How can we reproduce the issue?

```python
from qiskit.providers.fake_provider import GenericBackendV2
from qiskit import quantum_info as qi, transpile, QuantumCircuit

backend = GenericBackendV2(2, basis_gates=["rz", "rx", "rzz"])
qc = QuantumCircuit(2)
qc.unitary(qi.random_unitary(4), [0, 1])
isa = transpile(qc, target=backend.target)
```
this results in an error
```
TypeError: ParameterExpression with unbound parameters (dict_keys([Parameter(ϴ)])) cannot be cast to a float.
```
because it tries to get the unitary matrix of parameterized `RZZGate(Parameter(ϴ))` instruction.

On the other hand, it transpiles circuit when I directly specify the basis gates.
```python
isa = transpile(qc, basis_gates=["rz", "rx", "rzz"])
```

### What should happen?

- Qiskit transpiler should support arbitrary fractional two qubit basis gates, e.g. `RZX, RXX, RYY, RZZ, RXY, ...`.
- Transpiling with `Target` and giving `basis_gates` should behave identically.

This is related but might be a feature request; even if I give `RZXGate(Parameter(ϴ))` in the target, current synthesis algorithm only picks pi/4 rotation. The synthesis pass should consider another angle if there is possibility of reducing the circuit depth.

### Any suggestions?

No. I'm not familiar with synthesis passes.

### Additional contract requirements

- `generate_preset_pass_manager(optimization_level, basis_gates=None, target=None, seed_transpiler=None, **kwargs)` in `qiskit.transpiler.preset_passmanagers` returns a preset pass manager for the given optimisation level, optionally constrained by an explicit `basis_gates` list or a custom `target`. Running the returned pass manager on a `QuantumCircuit` returns a transpiled `QuantumCircuit`.
- `Operator.from_circuit(circuit)` in `qiskit.quantum_info` returns the `Operator` of a `QuantumCircuit`.
- `Target.add_instruction(instruction, qargs)` in `qiskit.transpiler.target` registers an instruction on the given qubit tuples.
