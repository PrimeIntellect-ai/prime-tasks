no validity check on Target construction
### Environment

- **Qiskit Terra version**:
- **Python version**:
- **Operating system**:


### What is happening?

It's possible to build a Target where the Instruction does not match the number of qubits it's being added to.

### How can we reproduce the issue?

For example here I add a 1-qubit gate to a two-qubit tuple.

```py
from qiskit.transpiler import Target, InstructionProperties
from qiskit.circuit.library import RZGate
from qiskit.circuit import Parameter

θ = Parameter('θ')
rz_props = {
    (0, 1): InstructionProperties(duration=0, error=0)
}

target = Target()
target.add_instruction(RZGate(θ), rz_props, name='rz')
```

### What should happen?

raise Error

### Any suggestions?

_No response_

### Additional contract requirements

- `Target.add_instruction(instruction, properties, name=None)` must raise `qiskit.transpiler.exceptions.TranspilerError` when a qargs tuple key in `properties` has a length that does not equal `instruction.num_qubits`.
