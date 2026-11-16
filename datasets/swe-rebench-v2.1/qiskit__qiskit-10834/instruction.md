Dynamical decoupling fails when a gate in the decoupling sequence has a calibration attached to the circuit
### Environment

- **Qiskit Terra version**: 0.25.1
- **Python version**: 3.10
- **Operating system**: Fedora Linux


### What is happening?

`PadDynamicalDecoupling` raises `TypeError: unhashable type: 'list'` when run on a circuit with a calibration for one of the gates in the decoupling sequence.

### How can we reproduce the issue?

```python
from qiskit_ibm_provider import IBMProvider


provider = IBMProvider()
backend = provider.get_backend("ibm_nazca")


import numpy as np

from qiskit import pulse, QuantumCircuit
from qiskit.transpiler import PassManager
from qiskit.transpiler.passes import ALAPScheduleAnalysis, PadDynamicalDecoupling
from qiskit.circuit.library import XGate, YGate
from qiskit.pulse import DriveChannel


inst_sched_map = backend.instruction_schedule_map


circ = QuantumCircuit(1, 1)
circ.x(0)
circ.delay(1600, 0)
circ.x(0)

for qubit in range(backend.configuration().n_qubits):
    with pulse.build(f"y gate for qubit {qubit}") as sched:
        with pulse.phase_offset(np.pi / 2, DriveChannel(qubit)):
            x_sched = inst_sched_map.get("x", qubits=[qubit])
            pulse.call(x_sched)
        circ.add_calibration("y", [qubit], sched)

dd_sequence = [XGate(), YGate()]*4
durations = backend.target.durations()

pm = PassManager(
        [
            ALAPScheduleAnalysis(durations),
            PadDynamicalDecoupling(
                durations,
                dd_sequence,
                pulse_alignment=backend.configuration().timing_constraints[
                    "pulse_alignment"
                ],
            ),
        ]
    )

pm.run(circ)
```

### What should happen?

The duration of the gate calibration should be used to schedule the decoupling sequence.

### Any suggestions?

A PR with a fix will be opened shortly.
