specifying nonexistent synthesis plugin does not raise error
### Environment

- **Qiskit Terra version**: 0.45.1
- **Python version**: 3.10.12
- **Operating system**: Arch Linux


### What is happening?

`generate_preset_pass_manager` does not raise an error for a nonexistent synthesis plugin, even though it does for a nonexistent stage plugin.

### How can we reproduce the issue?

```python
from qiskit.providers.fake_provider import FakeBelem
from qiskit.transpiler.preset_passmanagers import generate_preset_pass_manager

backend = FakeBelem()
pass_manager = generate_preset_pass_manager(
    optimization_level=3, backend=backend, unitary_synthesis_method="a"
)
```

### What should happen?

This does not raise an error. Instead, an error is raised when the pass manager is run. This is inconsistent with the transpiler stage plugins. For example, this raises an error:
```python
from qiskit.providers.fake_provider import FakeBelem
from qiskit.transpiler.preset_passmanagers import generate_preset_pass_manager

backend = FakeBelem()
pass_manager = generate_preset_pass_manager(
    optimization_level=3, backend=backend, routing_method="a"
)
```
```
TranspilerError: 'Invalid plugin name a for stage routing'
```

### Any suggestions?

The error should be raised when the pass manager is created, not when it is run.
