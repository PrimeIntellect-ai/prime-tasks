Transpiling fails if the target does not specify properties for measurement instructions
### Environment

- **Qiskit Terra version**: 0.22.0
- **Python version**: 3.9.12
- **Operating system**: Windows 10


### What is happening?

```
Traceback (most recent call last):
  File ".\src\playground.py", line 86, in <module>
    qc_transpiled = transpile(qc, target=target)
  [HIDDEN]
```

### How can we reproduce the issue?

When building a transpiler target, the properties for added instructions are optional. The documentation of `qiskit.transpiler.Target.add_instruction` says `Properties are optional for any instruction implementation, if there are no InstructionProperties available for the backend the value can be None.`. However, it seems this claim is true for all instructions except measurement.

The below code snippet shows how to construct a very simple target with one qubit and measurement instruction associated with it. The measurement instruction does not have any properties (i.e. it is specified as `None`). Then, this target is used to transpile a circuit, which results into the error pasted above
```
from qiskit import QuantumCircuit
from qiskit.circuit.library import Measure
from qiskit.compiler import transpile
from qiskit.transpiler import Target

target = Target()
target.add_instruction(Measure(), {(0,): None})

qc = QuantumCircuit(1, 1)
qc.measure(0, 0)

transpile(qc, target=target)
```

### What should happen?

The transpilation should not fail

### Any suggestions?

_No response_

### Additional contract requirements

- In the reproduced case, `transpile(qc, target=target)` raises an `AttributeError` when the measurement instruction's per-qubit properties are `None`; it must complete without raising.
