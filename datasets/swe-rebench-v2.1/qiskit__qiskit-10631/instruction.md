Cannot apply dynamical decoupling on a circuit with parameterized global phase
### Environment

- **Qiskit Terra version**: 0.25
- **Python version**: 3.11
- **Operating system**: Windows


### What is happening?

Dynamical decoupling cannot be applied on a circuit with a parameterized global phase, due to a failing `_mod_2pi` wrapping

### How can we reproduce the issue?

```python
from qiskit.transpiler.passes import ALAPScheduleAnalysis, PadDynamicalDecoupling
from qiskit.transpiler import PassManager, InstructionDurations
from qiskit.circuit.library import XGate
from qiskit.circuit import Parameter
durations = InstructionDurations.from_backend(backend)

qc = QuantumCircuit(1,1)
qc.sx(0)
qc.delay(1600, 0)
qc.sx(0)
qc.global_phase=Parameter('a')

pm = PassManager([ALAPScheduleAnalysis(durations), PadDynamicalDecoupling(durations, [XGate(), XGate()])])
pm.run(qc)
```

errors in
https://github.com/Qiskit/qiskit-terra/blob/c29e938c2ba1c359a0a3268679c68f3237b2c1b7/qiskit/transpiler/passes/scheduling/dynamical_decoupling.py#L260
with:
`TypeError: unsupported operand type(s) for %: 'ParameterExpression' and 'float'`

### What should happen?

Run the DD transpiler pass successfully

### Any suggestions?

[HIDDEN], see same issue in https://github.com/Qiskit/qiskit-ibm-provider/pull/689

### Additional contract requirements

- For the tested parameterized-global-phase case, the output circuit's global phase must equal the input circuit's global phase plus `np.pi`.
