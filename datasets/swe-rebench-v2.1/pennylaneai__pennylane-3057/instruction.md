[BUG] Matrix method of `qml.exp` doesn't utilize `wire_order`
### Expected behavior

Matrix method of `qml.exp` should utilize `wire_order` [HIDDEN].

### Actual behavior

Since `qml.eigvals` doesn't support `wire_order` currently, the matrix method of  `qml.exp` skips using `wire_order` and hence throws errors for observables with missing wires.

### Additional information

_No response_

### Source code

```shell
import pennylane as qml
from pennylane import numpy as np

op = qml.exp(qml.PauliZ(wires=[0]) @ qml.PauliY(wires=[1]) @ qml.PauliZ(wires=[4]), coeff=np.array(0.25))
qml.matrix(op)
```


### Tracebacks

```shell
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
Input In [21], in <cell line: 1>()
----> 1 qml.matrix(op)

File ~/workspace/.conda/envs/pennylane/lib/python3.9/site-packages/pennylane/transforms/op_transforms.py:213, in op_transform.__call__(self, *targs, **tkwargs)
    210     obj, *targs = targs
    212 if isinstance(obj, (qml.operation.Operator, qml.tape.QuantumTape)) or callable(obj):
--> 213     return self._create_wrapper(obj, *targs, **tkwargs)
    215 # Input is not an operator nor a QNode nor a quantum tape nor a qfunc.
    216 # Assume Python decorator syntax:
    217 #
   (...)
    229 # Prepend the input to the transform args,
    230 # and create a wrapper function.
    231 if obj is not None:

File ~/workspace/.conda/envs/pennylane/lib/python3.9/site-packages/pennylane/transforms/op_transforms.py:412, in op_transform._create_wrapper(self, obj, wire_order, *targs, **tkwargs)
    409     if wire_order is not None:
    410         tkwargs["wire_order"] = wire_order
--> 412     wrapper = self.fn(obj, *targs, **tkwargs)
    414 elif isinstance(obj, qml.tape.QuantumTape):
    415     # Input is a quantum tape. Get the quantum tape.
    416     tape, verified_wire_order = self._make_tape(obj, wire_order)

File ~/workspace/.conda/envs/pennylane/lib/python3.9/site-packages/pennylane/transforms/op_transforms.py:274, in op_transform.fn(self, obj, *args, **kwargs)
    265     return self.tape_fn(obj.expand(), *args, **kwargs)
    267 except (
    268     AttributeError,
    269     qml.operation.OperatorPropertyUndefined,
   (...)
    272     # if obj.expand() does not exist, a required operation property was not found,
    273     # or the tape transform function does not exist, simply raise the original exception
--> 274     raise e1 from None

File ~/workspace/.conda/envs/pennylane/lib/python3.9/site-packages/pennylane/transforms/op_transforms.py:258, in op_transform.fn(self, obj, *args, **kwargs)
    240 """Evaluate the underlying operator transform function.
    241
    242 If a corresponding tape transform for the operator has been registered
   (...)
    255     any: the result of evaluating the transform
    256 """
    257 try:
--> 258     return self._fn(obj, *args, **kwargs)
    260 except Exception as e1:  # pylint: disable=broad-except
    262     try:
    263         # attempt to decompose the operation and call
    264         # the tape transform function if defined

File ~/workspace/.conda/envs/pennylane/lib/python3.9/site-packages/pennylane/ops/functions/matrix.py:127, in matrix(op, wire_order)
    124 if isinstance(op, qml.Hamiltonian):
    125     return qml.utils.sparse_hamiltonian(op, wires=wire_order).toarray()
--> 127 return op.matrix(wire_order=wire_order)

File ~/workspace/.conda/envs/pennylane/lib/python3.9/site-packages/pennylane/ops/op_math/exp.py:180, in Exp.matrix(self, wire_order)
    [HIDDEN]
    181     return expand_matrix(mat, wires=self.wires, wire_order=wire_order)
    182 except OperatorPropertyUndefined:

File ~/workspace/.conda/envs/pennylane/lib/python3.9/site-packages/pennylane/numpy/tensor.py:155, in tensor.__array_ufunc__(self, ufunc, method, *inputs, **kwargs)
    151 args = [i.unwrap() if hasattr(i, "unwrap") else i for i in inputs]
    153 # call the ndarray.__array_ufunc__ method to compute the result
    154 # of the vectorized ufunc
--> 155 res = super().__array_ufunc__(ufunc, method, *args, **kwargs)
    157 if ufunc.nout == 1:
    158     res = (res,)

ValueError: matmul: Input operand 1 has a mismatch in its core dimension 0, with gufunc signature (n?,k),(k,m?)->(n?,m?) (size 8 is different from 2)
```


### System information

```shell
Name: PennyLane
Version: 0.26.0.dev0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/XanaduAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /home/jovyan/workspace/.conda/envs/pennylane/lib/python3.9/site-packages
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, retworkx, scipy, semantic-version, toml
Required-by: PennyLane-Cirq, PennyLane-Lightning, PennyLane-qiskit, pennylane-qulacs, PennyLane-SF

Platform info:           Linux-5.4.196-108.356.amzn2.x86_64-x86_64-with-glibc2.31
Python version:          3.9.13
Numpy version:           1.23.2
Scipy version:           1.9.1
Installed devices:
- default.gaussian (PennyLane-0.26.0.dev0)
- default.mixed (PennyLane-0.26.0.dev0)
- default.qubit (PennyLane-0.26.0.dev0)
- default.qubit.autograd (PennyLane-0.26.0.dev0)
- default.qubit.jax (PennyLane-0.26.0.dev0)
- default.qubit.tf (PennyLane-0.26.0.dev0)
- default.qubit.torch (PennyLane-0.26.0.dev0)
- default.qutrit (PennyLane-0.26.0.dev0)
- lightning.qubit (PennyLane-Lightning-0.25.1)
- cirq.mixedsimulator (PennyLane-Cirq-0.24.0)
- cirq.pasqal (PennyLane-Cirq-0.24.0)
- cirq.qsim (PennyLane-Cirq-0.24.0)
- cirq.qsimh (PennyLane-Cirq-0.24.0)
- cirq.simulator (PennyLane-Cirq-0.24.0)
- qiskit.aer (PennyLane-qiskit-0.24.0)
- qiskit.basicaer (PennyLane-qiskit-0.24.0)
- qiskit.ibmq (PennyLane-qiskit-0.24.0)
- qiskit.ibmq.circuit_runner (PennyLane-qiskit-0.24.0)
- qiskit.ibmq.sampler (PennyLane-qiskit-0.24.0)
- qulacs.simulator (pennylane-qulacs-0.24.0)
- strawberryfields.fock (PennyLane-SF-0.20.1)
- strawberryfields.gaussian (PennyLane-SF-0.20.1)
- strawberryfields.gbs (PennyLane-SF-0.20.1)
- strawberryfields.remote (PennyLane-SF-0.20.1)
- strawberryfields.tf (PennyLane-SF-0.20.1)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

- When `wire_order` is supplied, the matrix of `qml.exp` must represent the operator in that wire order, including when its diagonalizing gates act on fewer wires than the operator.
