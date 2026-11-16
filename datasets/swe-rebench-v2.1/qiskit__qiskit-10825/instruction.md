Unnecessary check and exception in `GateDirection` pass
### Environment

- **Qiskit Terra version**: 0.25
- **Python version**: 3.9
- **Operating system**: MacOS


### What is happening?

The `GateDirection` transpiler pass has an unnecessary check that input circuits only contain 1 register:

https://github.com/Qiskit/qiskit/blob/main/qiskit/transpiler/passes/utils/gate_direction.py#L328-L332


### How can we reproduce the issue?

```python
from qiskit.circuit import QuantumRegister, QuantumCircuit
from qiskit.transpiler import PassManager, CouplingMap
from qiskit.transpiler.passes import GateDirection

q1 = QuantumRegister(1)
q2 = QuantumRegister(1)
qc = QuantumCircuit(q1, q2)
qc.cx(1, 0)
qc.cx(0, 1)

cmap = CouplingMap([[0, 1]])
pm = PassManager([GateDirection(coupling_map=cmap)])
pm.run(qc)
```
raises
```
TranspilerError: "GateDirection expects a single qreg input DAG,but input DAG had qregs: OrderedDict([('q67', QuantumRegister(1, 'q67')), ('q68', QuantumRegister(1, 'q68'))])."
```

### What should happen?

[HIDDEN]
```python

class GateDirectionFixed(GateDirection):

[HIDDEN]

pm = PassManager([GateDirectionFixed(coupling_map=cmap)])
pm.run(qc).draw()
```
```
     ┌───┐     ┌───┐
q77: ┤ H ├──■──┤ H ├──■──
     ├───┤┌─┴─┐├───┤┌─┴─┐
q78: ┤ H ├┤ X ├┤ H ├┤ X ├
     └───┘└───┘└───┘└───┘
```

### Any suggestions?

[HIDDEN]

### Additional contract requirements

`GateDirection` must accept input containing multiple quantum registers and still apply its normal gate-direction handling. In particular, a gate whose operand order conflicts with the coupling map must be converted to an equivalent operation in the supported direction, even when the input uses multiple registers.
