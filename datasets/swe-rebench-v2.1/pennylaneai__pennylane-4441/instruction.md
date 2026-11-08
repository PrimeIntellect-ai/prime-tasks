[BUG] Unexpected behaviour with operator subtraction and `.simplify()`
### Expected behavior

I am trying to combine Pauli strings using addition/subtraction and tensor products. Subtracting operators from each other and simplifying the result should be possible. For example,

```
>>> H1 = qml.PauliZ(0)
>>> H2 = qml.prod(qml.PauliX(0), qml.PauliY(1))
>>> H = H1 - H2
>>> H.simplify()
```


### Actual behavior

Running the code above results in an error in the comparison portion of the `.simplify()` method that seems to be related specifically to the subtraction of one term from another when `qml.prod` is used to construct the second operand.

### Additional information

More examples in source code.

### Source code

```shell
# This throws the error in the traceback
H1 = qml.PauliZ(0)
H2 = qml.prod(qml.PauliX(0), qml.PauliY(1))
H = H1 - H2
H.simplify()

# It does not throw an error when a coefficient is added
H1 = qml.PauliZ(0)
H2 = qml.prod(qml.PauliX(0), qml.PauliY(1))
H = H1 - 1 * H2
H.simplify()

# Constructing the product with an @ seems to be okay too
H1 = qml.PauliZ(0)
H2 = qml.PauliX(0) @ qml.PauliY(1)
H = H1 - H2
H.simplify()
```


### Tracebacks

```shell
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
Cell In[24], line 4
      2 H2 = qml.prod(qml.PauliX(0), qml.PauliY(1))
      3 H = H1 - H2
----> 4 H.simplify()

File ~/Code/pennylane/pennylane/ops/op_math/sum.py:299, in Sum.simplify(self, cutoff)
    296     pr.simplify()
    297     return pr.operation(wire_order=self.wires)
--> 299 new_summands = self._simplify_summands(summands=self.operands).get_summands(cutoff=cutoff)
    300 if new_summands:
    301     return Sum(*new_summands) if len(new_summands) > 1 else new_summands[0]

File ~/Code/pennylane/pennylane/ops/op_math/sum.py:283, in Sum._simplify_summands(cls, summands)
    280         new_summands.add(summand=sum_summand, coeff=coeff, op_hash=op_hash)
    281     continue
--> 283 simplified_summand = summand.simplify()
    284 if isinstance(simplified_summand, Sum):
    285     sum_summands = cls._simplify_summands(summands=simplified_summand.operands)

File ~/Code/pennylane/pennylane/ops/op_math/sprod.py:296, in SProd.simplify(self)
    293     pr.simplify()
    294     return pr.operation(wire_order=self.wires)
--> 296 if self.scalar == 1:
    297     return self.base.simplify()
    298 if isinstance(self.base, SProd):

ValueError: The truth value of an array with more than one element is ambiguous. Use a.any() or a.all()
```


### System information

```shell
# Running on dev version, commit 4ff58e5030139c13ec09a712f9e8a5f6c4c1b517

Name: PennyLane
Version: 0.32.0.dev0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/PennyLaneAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /home/olivia/.conda/envs/xanadu/lib/python3.9/site-packages
Editable project location: /home/olivia/Code/pennylane
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, requests, rustworkx, scipy, semantic-version, toml
Required-by: PennyLane-IonQ, PennyLane-Lightning, PennyLane-Qchem, PennyLane-qiskit

Platform info:           Linux-6.0.0-060000-generic-x86_64-with-glibc2.35
Python version:          3.9.7
Numpy version:           1.22.2
Scipy version:           1.9.1
Installed devices:
- default.gaussian (PennyLane-0.32.0.dev0)
- default.mixed (PennyLane-0.32.0.dev0)
- default.qubit (PennyLane-0.32.0.dev0)
- default.qubit.autograd (PennyLane-0.32.0.dev0)
- default.qubit.jax (PennyLane-0.32.0.dev0)
- default.qubit.tf (PennyLane-0.32.0.dev0)
- default.qubit.torch (PennyLane-0.32.0.dev0)
- default.qutrit (PennyLane-0.32.0.dev0)
- null.qubit (PennyLane-0.32.0.dev0)
- qiskit.aer (PennyLane-qiskit-0.30.1)
- qiskit.basicaer (PennyLane-qiskit-0.30.1)
- qiskit.ibmq (PennyLane-qiskit-0.30.1)
- qiskit.ibmq.circuit_runner (PennyLane-qiskit-0.30.1)
- qiskit.ibmq.sampler (PennyLane-qiskit-0.30.1)
- lightning.qubit (PennyLane-Lightning-0.31.0)
- ionq.qpu (PennyLane-IonQ-0.28.0)
- ionq.simulator (PennyLane-IonQ-0.28.0)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.
