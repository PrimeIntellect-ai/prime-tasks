QASM 3 exporter does not respect non-standard basis gates
### Environment

- **Qiskit Terra version**: 0.20.2
- **Python version**: any
- **Operating system**: any


### What is happening?

The OpenQASM 3 exporter is not correctly handling non-standard (user-defined) gates put in `basis_gates`.  This is useful when the backend supplies some gates that Terra does not have decompositions for; one should be able to add the gate as an opaque gate, and use the `basis_gates` argument to cause Terra to treat it as having some external definition.  The transpiler does this correctly, but not the QASM 3 exporter.

### How can we reproduce the issue?

```python
from qiskit import QuantumCircuit, qasm3
from qiskit.circuit import Gate

qc = QuantumCircuit(1)
qc.x(0)
qc.append(Gate("my_gate", 1, []), [0], [])

qasm3.dumps(qc, basis_gates=["my_gate"])
```
results in an error from trying to export an opaque instruction:
```
---------------------------------------------------------------------------
QASM3ExporterError                        Traceback (most recent call last)
<ipython-input-2-5db45ede210a> in <module>
      6 qc.append(Gate("my_gate", 1, []), [0], [])
      7
----> 8 qasm3.dumps(qc, basis_gates=["my_gate"])

~/code/qiskit/terra/qiskit/qasm3/__init__.py in dumps(circuit, **kwargs)
     47         str: The OpenQASM3 serialization
     48     """
---> 49     return Exporter(**kwargs).dumps(circuit)
     50
     51

~/code/qiskit/terra/qiskit/qasm3/exporter.py in dumps(self, circuit)
    151         """Convert the circuit to QASM 3, returning the result as a string."""
    152         with io.StringIO() as stream:
--> 153             self.dump(circuit, stream)
    154             return stream.getvalue()
    155

~/code/qiskit/terra/qiskit/qasm3/exporter.py in dump(self, circuit, stream)
    163             alias_classical_registers=self.alias_classical_registers,
    164         )
--> 165         BasicPrinter(stream, indent=self.indent).visit(builder.build_program())
    166
    167

~/code/qiskit/terra/qiskit/qasm3/exporter.py in build_program(self)
    400         """Builds a Program"""
    401         self.hoist_declarations(self.global_scope(assert_=True).circuit.data)
--> 402         return ast.Program(self.build_header(), self.build_global_statements())
    403
    404     def hoist_declarations(self, instructions):

~/code/qiskit/terra/qiskit/qasm3/exporter.py in build_global_statements(self)
    518             ;
    519         """
--> 520         definitions = self.build_definitions()
    521         inputs, outputs, variables = self.build_variable_declarations()
    522         bit_declarations = self.build_classical_declarations()

~/code/qiskit/terra/qiskit/qasm3/exporter.py in build_definitions(self)
    548         ret = []
    549         for instruction in self._opaque_to_declare.values():
--> 550             ret.append(self.build_definition(instruction, self.build_opaque_definition))
    551         for instruction in self._subroutine_to_declare.values():
    552             ret.append(self.build_definition(instruction, self.build_subroutine_definition))

~/code/qiskit/terra/qiskit/qasm3/exporter.py in build_definition(self, instruction, builder)
    562             pass
    563         self._flat_reg = True
--> 564         definition = builder(instruction)
    565         self._flat_reg = False
    566         return definition

~/code/qiskit/terra/qiskit/qasm3/exporter.py in build_opaque_definition(self, instruction)
    569         """Builds an Opaque gate definition as a CalibrationDefinition"""
    570         # We can't do anything sensible with this yet, so it's better to loudly say that.
--> 571         raise QASM3ExporterError(
    572             "Exporting opaque instructions with pulse-level calibrations is not yet supported by"
    573             " the OpenQASM 3 exporter. Received this instruction, which appears opaque:"

QASM3ExporterError: "Exporting opaque instructions with pulse-level calibrations is not yet supported by the OpenQASM 3 exporter. Received this instruction, which appears opaque:\nInstruction(name='my_gate', num_qubits=1, num_clbits=0, params=[])"
```

### What should happen?

The error would be correct if the gate was truly opaque, but since it's passed in `basis_gates`, it should instead be output with no definition.

### Any suggestions?

[HIDDEN]
