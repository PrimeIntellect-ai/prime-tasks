[BUG] Error when multiplying certain Hamiltonian observables
### Expected behavior

I've been playing around with the different observable types in Pennylane and noticed we do support multiplying Hamiltonians together, both from tensor products of Paulis and from Hermitian observables:

```py
import pennylane as qml

tensor = qml.PauliX(0) @ qml.PauliX(1)
herm = qml.Hermitian([[1,0], [0,1]], wires=4)

qml.Hamiltonian([1.0], [tensor]) @ qml.Hamiltonian([1.0], [herm])
```

### Actual behavior

However, for this case I get an unexpected error:

```py
import pennylane as qml

tensor = qml.PauliX(0) @ qml.PauliX(1)
herm = qml.Hermitian([[1,0], [0,1]], wires=4)

qml.Hamiltonian([1.0, 1.0], [tensor, qml.PauliX(2)]) @ qml.Hamiltonian([1.0], [herm])
```

### Additional information

_No response_

### Source code

_No response_

### Tracebacks

```shell
AttributeError                            Traceback (most recent call last)
Untitled-1.ipynb Cell 5 in <cell line: 6>()
      3 tensor = qml.PauliX(0) @ qml.PauliX(1)
      4 herm = qml.Hermitian([[1,0], [0,1]], wires=4)
----> 6 qml.Hamiltonian([1.0, 1.0], [tensor, qml.PauliX(2)]) @ qml.Hamiltonian([1.0], [herm])

File ~/.local/lib/python3.10/site-packages/pennylane/ops/qubit/hamiltonian.py:543, in Hamiltonian.__matmul__(self, H)
    540     ops_list = itertools.product(ops1, ops2)
    541     terms = [qml.operation.Tensor(t[0], t[1]) for t in ops_list]
--> 543     return qml.Hamiltonian(coeffs, terms, simplify=True)
    545 if isinstance(H, (Tensor, Observable)):
    546     terms = [op @ H for op in ops1]

File ~/.local/lib/python3.10/site-packages/pennylane/ops/qubit/hamiltonian.py:203, in Hamiltonian.__init__(self, coeffs, observables, simplify, grouping_type, method, id, do_queue)
    200 self._grouping_indices = None
    202 if simplify:
--> 203     self.simplify()
    204 if grouping_type is not None:
    205     with qml.tape.stop_recording():

File ~/.local/lib/python3.10/site-packages/pennylane/ops/qubit/hamiltonian.py:374, in Hamiltonian.simplify(self)
    371 c = self.coeffs[i]
    372 op = op if isinstance(op, Tensor) else Tensor(op)
--> 374 ind = next((j for j, o in enumerate(new_ops) if op.compare(o)), None)
...
-> 1589     [HIDDEN]
   1590     tensor.add((ob.name, ob.wires, parameters))
   1592 return tensor

AttributeError: 'list' object has no attribute 'tobytes'
```


### System information

```shell
Name: PennyLane
Version: 0.26.0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/XanaduAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /home/david/.local/lib/python3.10/site-packages
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, retworkx, scipy, semantic-version, toml
Required-by: PennyLane-Lightning

Platform info:           Linux-5.15.0-1020-aws-x86_64-with-glibc2.31
Python version:          3.10.7
Numpy version:           1.22.4
Scipy version:           1.8.1
Installed devices:
- lightning.qubit (PennyLane-Lightning-0.26.0)
- default.gaussian (PennyLane-0.26.0)
- default.mixed (PennyLane-0.26.0)
- default.qubit (PennyLane-0.26.0)
- default.qubit.autograd (PennyLane-0.26.0)
- default.qubit.jax (PennyLane-0.26.0)
- default.qubit.tf (PennyLane-0.26.0)
- default.qubit.torch (PennyLane-0.26.0)
- default.qutrit (PennyLane-0.26.0)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

- Multiplying Hamiltonians as in the reported example, including a multi-term Hamiltonian containing a tensor-product Pauli and a Hamiltonian containing a Hermitian observable, must not raise an error. The result must represent the operator product of the two Hamiltonians.
