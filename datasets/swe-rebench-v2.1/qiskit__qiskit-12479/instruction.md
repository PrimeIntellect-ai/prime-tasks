EvolvedOperatorAnsatz with an empty list of operators
### Environment

- **Qiskit version**: 0.45.2
- **Python version**: 3.11.6
- **Operating system**: GNU/Linux


### What is happening?

If we set `operators` in [EvolvedOperatorAnsatz](https://docs.quantum.ibm.com/api/qiskit/qiskit.circuit.library.EvolvedOperatorAnsatz) to an empty list, it raises an unhandled exception and fails to create an object.

This case can happen when we use [UCCSD](https://qiskit-community.github.io/qiskit-nature/stubs/qiskit_nature.second_q.circuit.library.UCCSD.html) ansatz from qiskit_nature with a molecule that has no electrons.

### How can we reproduce the issue?

Running the following code
```python
from qiskit.circuit.library import EvolvedOperatorAnsatz
from qiskit import QuantumCircuit

e = EvolvedOperatorAnsatz(operators=[])
e == QuantumCircuit()
```
raises the following error:
```
File "/..../site-packages/qiskit/circuit/library/evolved_operator_ansatz.py", line 109, in num_qubits
    return self.operators.num_qubits
           ^^^^^^^^^^^^^^^^^^^^^^^^^
AttributeError: 'list' object has no attribute 'num_qubits'
```

### What should happen?

It was expected to return `True` as the case with no qubit is handled well in `QuantumCircuit` and its subclasses. It was partially handled in the `EvolvedOperatorAnsatz` too. For example
https://github.com/Qiskit/qiskit/blob/d033e8a4185c0299b644f0bdf4e8ed1d17d2bb08/qiskit/circuit/library/n_local/evolved_operator_ansatz.py#L109
  shows the previous intention to handle this case. But it is not completely done so it raises an unhandled exception.

### Any suggestions?

I'll create a pull request to discuss the proposed solution.
