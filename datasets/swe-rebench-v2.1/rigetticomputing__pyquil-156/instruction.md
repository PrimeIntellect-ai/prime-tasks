get_qubits doesn't return qubits in Instr's
I would expect the following to include `0`.
```
>>> from pyquil.quil import Program
>>> p = Program()
>>> p.inst(("H",0))
<pyquil.quil.Program object at 0x7fc71e298290>
>>> p.get_qubits()
set([])
>>>
```
