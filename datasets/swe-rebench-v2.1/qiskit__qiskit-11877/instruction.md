qiskit.provider.back_compat.convert_to_target doesn't add control flow instructions to the target
### Environment

- **Qiskit version**: 1.0
- **Python version**: 3.11.7
- **Operating system**: macOS 13.6


### What is happening?

`convert_to_target` doesn't populate the target with control flow instructions.

### How can we reproduce the issue?

Example using an IBM backend, but the problem is not due to the `qiskit_ibm_runtime`.

```python
from qiskit_ibm_runtime import QiskitRuntimeService

# pick any Eagle backend
backend = service.get_backend("ibm_brisbane")

set(instr.name for instr, qargs in backend.target.instructions)
```

will be missing `if_else`, `for_loop`, and `switch_case`.

Following the chain, you see that `backend.target` is calling:
```python
convert_to_target(
                configuration=self._configuration,
                properties=self._properties,
                defaults=self._defaults,
            )
```

### What should happen?

The control flow operations should be in the target instructions.

### Any suggestions?

The issue seems to be that `convert_to_target` [populates a value](https://github.com/Qiskit/qiskit/blob/main/qiskit/providers/backend_compat.py#L94) [HIDDEN] [HIDDEN]

### Additional contract requirements

- When `if_else`, `for_loop`, or `switch_case` is declared in a backend configuration's `supported_instructions`, `convert_to_target` must include that operation in the returned target's instructions.
