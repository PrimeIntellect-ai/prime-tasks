marginal_counts does not act on memory field
### Environment

- **Qiskit Terra version**:  0.20
- **Python version**:  3.8
- **Operating system**:  Windows 10


### What is happening?

The `marginal_counts` method acts on a `Result` by marginalizing the counts in the `ExperimentResultData` object. It does act on the `counts` field, but not in the `memory` field.

### How can we reproduce the issue?

A minimal example:
```
from qiskit.circuit import QuantumCircuit
from qiskit import Aer
from qiskit.result import marginal_counts

b=Aer.get_backend('qasm_simulator')

qc=QuantumCircuit(2)
qc.h(0)
qc.h(1)
qc.measure_all()

result=b.run([qc], shots=50, memory=True).result()
print(result.results[0].data)

marginal_result=marginal_counts(result, indices=[1] )
data=marginal_result.results[0].data
print(data)
```
The results in the fields `counts` and `memory` from  `data` are not consistent.

### What should happen?

The memory field should be updated by the `marginal_counts` method. (or as a fallback: the `memory` field should be made empty)

### Any suggestions?

_No response_
