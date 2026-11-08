ControlFlow context manager places "composed" elements outside scope
### Environment

- **Qiskit Terra version**: 0.21.0rc1-45
- **Python version**: 3.10
- **Operating system**: Linux


### What is happening?

When using the `compose` method within a ControlFlow context builder the composed element is inserted at the top level scope.



### How can we reproduce the issue?

```python
from qiskit.circuit.library.standard_gates.x import CCXGate
qreg = QuantumRegister(3)
creg = ClassicalRegister(3)
circ = QuantumCircuit(qreg, creg)
with circ.for_loop(range(3)):
    circ.x(qreg)
    circ.compose(CCXGate().definition, inplace=True)
print(circ)
```

yields,

```
                                                        ┌───┐      ┌───────────┐
q0_0: ───────────────────■─────────────────────■────■───┤ T ├───■──┤0          ├
                         │             ┌───┐   │  ┌─┴─┐┌┴───┴┐┌─┴─┐│           │
q0_1: ───────■───────────┼─────────■───┤ T ├───┼──┤ X ├┤ Tdg ├┤ X ├┤1 For_loop ├
      ┌───┐┌─┴─┐┌─────┐┌─┴─┐┌───┐┌─┴─┐┌┴───┴┐┌─┴─┐├───┤└┬───┬┘└───┘│           │
q0_2: ┤ H ├┤ X ├┤ Tdg ├┤ X ├┤ T ├┤ X ├┤ Tdg ├┤ X ├┤ T ├─┤ H ├──────┤2          ├
      └───┘└───┘└─────┘└───┘└───┘└───┘└─────┘└───┘└───┘ └───┘      └───────────┘
c0: 3/══════════════════════════════════════════════════════════════════════════
```

### What should happen?

The composed circuit should appear inside the `for-loop` as an appended instruction currently does.

### Any suggestions?

_No response_
