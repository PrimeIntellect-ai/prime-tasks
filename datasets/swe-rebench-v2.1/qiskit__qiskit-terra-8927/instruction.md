`'NoneType' object has no attribute 'metadata'` when trying to serialize custom gate on `qiskit-terra==0.21.2` when it used to work on `qiskit-terra==0.21.1`
### Environment

- **Qiskit Terra version**: 0.21.2
- **Python version**: 3.8.13
- **Operating system**: Ubuntu


### What is happening?

Qsikit errors out when trying to serial a circuit which contains a custom gate, when it used to work before on `qiskit-terra==0.21.1`

### How can we reproduce the issue?

Run

```python
import io
from typing import Optional, Union

import numpy as np
import qiskit
from qiskit.circuit.library import XGate
from qiskit.qpy import dump

class CustomCXGate(qiskit.circuit.ControlledGate):
    def __init__(
        self, label: Optional[str] = None, ctrl_state: Optional[Union[str, int]] = None
    ) -> None:
        super().__init__(
            "cx", 2, [], label, num_ctrl_qubits=1, ctrl_state=ctrl_state, base_gate=XGate()
        )

    def _define(self) -> None:
        qc = qiskit.QuantumCircuit(2, name=self.name)
        qc.cx(0, 1)
        self.definition = qc

    def __array__(self, dtype: Optional[type] = None) -> np.ndarray:
        mat = qiskit.circuit._utils._compute_control_matrix(
            self.base_gate.to_matrix(), self.num_ctrl_qubits, ctrl_state=self.ctrl_state
        )
        return np.asarray(mat, dtype=dtype)

circuit = qiskit.QuantumCircuit(2)
circuit.append(CustomCXGate(),[0, 1])
buf = io.BytesIO()
dump(circuit, buf)
```

This will throw an error

```
circuit.metadata, separators=(",", ":"), cls=metadata_serializer
AttributeError: 'NoneType' object has no attribute 'metadata'

```


### What should happen?

The above snippet should run with no errors.

### Any suggestions?

_No response_
