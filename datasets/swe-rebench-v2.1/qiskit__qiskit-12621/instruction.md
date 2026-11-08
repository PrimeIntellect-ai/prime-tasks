Parameter cache is preserved after copy_empty_like
### Environment

- **Qiskit version**: main
- **Python version**:
- **Operating system**:


### What is happening?

Parameter appears in empty circuit after copy

### How can we reproduce the issue?

```python
p1 = Parameter("P1")
qc = QuantumCircuit(1)
qc.rz(p1, 0)
qc.parameters  # dummy call to fill cache

cpy = qc.copy_empty_like()
cpy.parameters
```
I see
```
ParameterView([Parameter(P1)])
```
which should not exist.

### What should happen?

Parameter should be empty

### Any suggestions?

[HIDDEN]
