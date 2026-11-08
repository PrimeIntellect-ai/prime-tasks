Qasm3 exporter failing when if branch does not contain all clbits
### Environment

- **Qiskit Terra version**: 0.39.0
- **Python version**: 3.10.6
- **Operating system**: MacOs 12.6 (21G115)


### What is happening?

In some cases, the qasm3 exporter gives an error if the circuit has more clbits than needed in the if_else statement.

### How can we reproduce the issue?

Run the following:

```
backend_wellington = provider.get_backend('ibm_wellington')

cr = ClassicalRegister(1) # if >1 breaks
cr2 = ClassicalRegister(1) # if this reg exists, breaks
qr = QuantumRegister(5)
qc = QuantumCircuit(qr, cr, cr2)

with qc.if_test((cr[0], 1)) as _:
    qc.cnot(0,1)
    qc.cnot(0,2)
    qc.cnot(0,3)
    qc.cnot(0,4)

qc_trans = transpile(qc, backend=backend_wellington, basis_gates=backend_wellington.configuration().basis_gates+['if_else'], optimization_level=1)
print(qasm3.Exporter().dumps(qc))
print(qasm3.Exporter().dumps(qc_trans))
```

Now, `qc` gets correctly exported, while `qc_trans` provides the following error:
```
QASM3ExporterError: 'Tried to push a scope whose circuit needs 2 clbits, but only provided 1 clbits to create the mapping.'
```

### What should happen?

The QASM3 string should be output for both cases.

### Any suggestions?

_No response_
