Converting custom pulse play instructions to Qobj raises an error
### Environment

- **Qiskit version**: 1.0
- **Python version**: 3.9
- **Operating system**: Windows


### What is happening?

When you try to convert to Qobj a circuit with a custom pulse in it, a `QiskitError` is raised.

### How can we reproduce the issue?

```python
import qiskit
from qiskit import pulse
from qiskit import circuit
from qiskit.providers.fake_provider import GenericBackendV2

with pulse.build() as sch:
    pulse.play(pulse.Triangle(32, 0.1, 0.2), pulse.DriveChannel(0))

qc = circuit.QuantumCircuit(1, 1)
qc.x(0)
qc.measure_all()
qc.add_calibration("x", (0,), sch)

transpiled = qiskit.transpile(qc, backend=GenericBackendV2(2))

qiskit.assemble(transpiled)
```
The pulse choice here is immaterial, as long as it is a pulse type which ~~is not recognized by the backend~~ does not appear in [ParametricPulseShapes](https://github.com/Qiskit/qiskit/blob/12f24a76b6fbba4ebd9d7cf09c42f2c6c6e3c8f7/qiskit/qobj/converters/pulse_instruction.py#L35). `Triangle` ~~is not recognized by the backend~~ does not appear there. ~~(Edit - `GenericBackendV2` doesn't define the field `parametric_pulses` so all pulse types will behave the same way here).~~

### What should happen?

The circuit should convert successfully to Qobj.

### Any suggestions?

[HIDDEN]
