`Target.has_calibration` errors for instructions without properties
### Environment

- **Qiskit version**: 1.1.0
- **Python version**: 3.12
- **Operating system**: Fedora Linux 40


### What is happening?

If a `Target` has an `Instruction` with `None` for its `InstructionProperties`, `Target.has_calibration` raises an `AttributeError`.

### How can we reproduce the issue?

Consider this case from the `Target` docstring with the `has_calibration` call added at the end:

```python
from qiskit.circuit.library import CXGate
from qiskit.transpiler import Target, InstructionProperties

target = Target()
cx_properties = {
    (0, 1): None,
    (1, 0): None,
    (0, 2): None,
    (2, 0): None,
    (0, 3): None,
    (2, 3): None,
    (3, 0): None,
    (3, 2): None
}
target.add_instruction(CXGate(), cx_properties)

target.has_calibration("cx", (0, 1))  # AttributeError!
```

### What should happen?

The last line above should return `False`

### Any suggestions?

I will submit a PR.
