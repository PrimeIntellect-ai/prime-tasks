Result.utils.marginal_counts returns inconsistent creg structure for multiple cregs
<!-- ⚠️ If you do not respect this template, your issue will be closed -->
<!-- ⚠️ Make sure to browse the opened and closed issues -->

### Information

- **Qiskit Terra version**: master @ d26f273d
- **Python version**: 3.6
- **Operating system**: osx

### Steps to reproduce the problem

```python
from qiskit import *

qr_data = QuantumRegister(3, 'qr_data')
qr_anc = QuantumRegister(2, 'qr_anc')
cr_data = ClassicalRegister(3, 'cr_data')
cr_anc = ClassicalRegister(2, 'cr_anc')

qc = QuantumCircuit(qr_data, qr_anc, cr_data, cr_anc)
qc.x(qr_data)
qc.measure(qr_data, cr_data)
qc.measure(qr_anc, cr_anc)
qc.draw('mpl')
```
![image](https://user-images.githubusercontent.com/766693/101812675-aaaa2380-3ae9-11eb-9d8a-cfe8c0afc6d1.png)

```python
result = execute(qc, Aer.get_backend('qasm_simulator')).result()
result.get_counts()
```
```
{'00 111': 1024}
```

```python
from qiskit.result.utils import marginal_counts
marginal_counts(result, [0, 1, 2]).get_counts()
```
```
{'11 1': 1024}
```
### What is the expected behavior?



### Suggested solutions

### Additional contract requirements

When `marginal_counts` is applied to a `Result` with multiple classical registers, retained indices are classical-bit positions in the original counts. The returned count keys must contain the values for those positions, in the same bit order used by `get_counts`. The returned metadata must preserve the original register ordering and names while setting each register's size to the number of retained bits from that register. The spaces displayed between groups in `get_counts` must then correspond to these updated register sizes, with no stale boundary from a register's original size.
