`pulse.build()` raises an error when `default_alignment` is set to `AlignmentKind` instance
### Environment

- **Qiskit version**: main
- **Python version**: 3.9
- **Operating system**: windows


### What is happening?

`pulse.build()` raises an error when `default_alignment` is set to `AlignmentKind` instance.

### How can we reproduce the issue?

```python
from qiskit.pulse import build
from qiskit.pulse.transforms import AlignLeft

with build(default_alignment=AlignLeft()) as schblock:
  pass

### What should happen?

The builder should accept the `AlignmentKind` instance as valid input, and set it as the default alignment.

### Any suggestions?

This [line](https://github.com/Qiskit/qiskit/blob/8557369597c7c7f3a0abe3f8b07045752ec10061/qiskit/pulse/builder.py#L534) assumes string identifier input, and ignores the possibility of `AlignmentKind` instance input.
