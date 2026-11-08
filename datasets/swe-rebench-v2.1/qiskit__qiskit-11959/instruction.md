`EquivalenceLibrary.set_entry` does not clear old entries in graph
### Environment

- **Qiskit version**: 1.0.1
- **Python version**: 3.10
- **Operating system**: macOS


### What is happening?

When using `EquivalenceLibrary.set_entry` to replace a set of entries with another, the `get_entry` method will update with the new entries, but the `graph` attribute will not have suitably changed the edges, meaning that the `BasisTranslator` will use the old rules.

### How can we reproduce the issue?

```python
import math
from qiskit.transpiler.passes import BasisTranslator
from qiskit.circuit.equivalence import EquivalenceLibrary
from qiskit.circuit import library, QuantumCircuit

equiv = EquivalenceLibrary()

cx_to_cz = QuantumCircuit(2)
cx_to_cz.ry(-math.pi / 4, 1)
cx_to_cz.cz(0, 1)
cx_to_cz.ry(math.pi / 2, 1)
equiv.add_equivalence(library.CXGate(), cx_to_cz)

cx_to_cz_worse = QuantumCircuit(2, global_phase=math.pi)
cx_to_cz_worse.ry(math.pi / 2, 1)
cx_to_cz_worse.rx(math.pi, 1)
cx_to_cz_worse.cz(0, 1)
cx_to_cz_worse.ry(math.pi / 2, 1)
cx_to_cz_worse.rx(math.pi, 1)
equiv.set_entry(library.CXGate(), [cx_to_cz_worse])

qc = QuantumCircuit(2)
qc.cx(0, 1)
BasisTranslator(equiv, ["cz", "rx", "ry", "rz"])(qc).draw()
```
```

q_0: ─────────────■────────────
     ┌──────────┐ │ ┌─────────┐
q_1: ┤ Ry(-π/4) ├─■─┤ Ry(π/2) ├
     └──────────┘   └─────────┘
```

### What should happen?

Since we replaced the "good" rule with a "bad" rule, the basis translator should only be able to find the bad rule and the output should be:
```
global phase: π

q_0: ─────────────────────■─────────────────────
     ┌─────────┐┌───────┐ │ ┌─────────┐┌───────┐
q_1: ┤ Ry(π/2) ├┤ Rx(π) ├─■─┤ Ry(π/2) ├┤ Rx(π) ├
     └─────────┘└───────┘   └─────────┘└───────┘
```

### Any suggestions?

_No response_
