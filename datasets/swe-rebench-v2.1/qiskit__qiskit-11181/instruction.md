`BlueprintCircuit` subclasses rebuild out-of-order after `_append`
### Environment

- **Qiskit Terra version**: 0.25.3
- **Python version**: 3.10
- **Operating system**: macOS


### What is happening?

Subclasses of `BlueprintCircuit` do not behave correctly when the inner-loop `_append` method is used; the circuit is not rebuilt prior to accepting the append.

### How can we reproduce the issue?

```python
from qiskit.circuit.library import RealAmplitudes, XGate
from qiskit.circuit import CircuitInstruction, ClassicalRegister

qc = RealAmplitudes(num_qubits=2, reps=2)
qc.add_register(ClassicalRegister(2, "meas"))
qc._append(CircuitInstruction(XGate(), (qc.qubits[0],), ()))
qc.draw()
```
gives
```
        ┌───┐┌────────────────────────────────────────────────┐
   q_0: ┤ X ├┤0                                               ├
        └───┘│  RealAmplitudes(θ[0],θ[1],θ[2],θ[3],θ[4],θ[5]) │
   q_1: ─────┤1                                               ├
             └────────────────────────────────────────────────┘
meas: 2/═══════════════════════════════════════════════════════
```

whereas using `QuantumCircuit.append` gives the expected:
```python
from qiskit.circuit.library import RealAmplitudes, XGate
from qiskit.circuit import CircuitInstruction, ClassicalRegister

qc = RealAmplitudes(num_qubits=2, reps=2)
qc.add_register(ClassicalRegister(2, "meas"))
qc.append(XGate(), [qc.qubits[0]])
qc.draw()
```
```
        ┌────────────────────────────────────────────────┐┌───┐
   q_0: ┤0                                               ├┤ X ├
        │  RealAmplitudes(θ[0],θ[1],θ[2],θ[3],θ[4],θ[5]) │└───┘
   q_1: ┤1                                               ├─────
        └────────────────────────────────────────────────┘
meas: 2/═══════════════════════════════════════════════════════
```

### What should happen?

Inner `_append` should handle enforcing the build, not `append`.

### Any suggestions?

_No response_
