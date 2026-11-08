GradientDescentOptimizer fails when `inv()` is used in circuit
Description of the issue

An error is thrown when trying to perform gradient descent on a simple circuit containing an inverse gate

* *Expected behavior:* circuits with inverse gates can be optimized without error

* *Actual behavior:* GradientDescentOptimizer fails when `inv()` is used in circuit

* *Reproduces how often:* every time

* *System information:*

```
Name: PennyLane
Version: 0.14.0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/XanaduAI/pennylane
Author: None
Author-email: None
License: Apache License 2.0
Location: /home/nathan/anaconda3/lib/python3.7/site-packages
Requires: autograd, numpy, scipy, toml, networkx, semantic-version, appdirs
Required-by: PennyLane-SF, PennyLane-Cirq, PennyLane-Orquestra
Platform info:           Linux-5.4.0-65-generic-x86_64-with-debian-bullseye-sid
Python version:          3.7.6
Numpy version:           1.18.1
Scipy version:           1.4.1
Installed devices:
- default.gaussian (PennyLane-0.14.0)
- default.mixed (PennyLane-0.14.0)
- default.qubit (PennyLane-0.14.0)
- default.qubit.autograd (PennyLane-0.14.0)
- default.qubit.jax (PennyLane-0.14.0)
- default.qubit.tf (PennyLane-0.14.0)
- default.tensor (PennyLane-0.14.0)
- default.tensor.tf (PennyLane-0.14.0)
- strawberryfields.fock (PennyLane-SF-0.12.0)
- strawberryfields.gaussian (PennyLane-SF-0.12.0)
- strawberryfields.gbs (PennyLane-SF-0.12.0)
- strawberryfields.remote (PennyLane-SF-0.12.0)
- strawberryfields.tf (PennyLane-SF-0.12.0)
- cirq.mixedsimulator (PennyLane-Cirq-0.10.0.dev0)
- cirq.pasqal (PennyLane-Cirq-0.10.0.dev0)
- cirq.simulator (PennyLane-Cirq-0.10.0.dev0)
- orquestra.forest (PennyLane-Orquestra-0.13.0.dev0)
- orquestra.ibmq (PennyLane-Orquestra-0.13.0.dev0)
- orquestra.qiskit (PennyLane-Orquestra-0.13.0.dev0)
- orquestra.qulacs (PennyLane-Orquestra-0.13.0.dev0)

```

#### Source code and tracebacks
```
>>> import pennylane as qml
>>> dev = qml.device('default.qubit', wires=2)
>>> @qml.qnode(dev)
... def circuit(x):
...     qml.RZ(x, wires=1).inv()
...     return qml.expval(qml.PauliZ(0))
...
>>> circuit(0)
tensor(1., requires_grad=True)
>>> opt = qml.GradientDescentOptimizer(0.1)
>>> x0 = 0.5
>>> opt.step(circuit, x0)
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/nathan/anaconda3/lib/python3.7/site-packages/pennylane/optimize/gradient_descent.py", line 98, in step
    g, _ = self.compute_grad(objective_fn, args, kwargs, grad_fn=grad_fn)
  File "/home/nathan/anaconda3/lib/python3.7/site-packages/pennylane/optimize/gradient_descent.py", line 127, in compute_grad
    grad = g(*args, **kwargs)
  File "/home/nathan/anaconda3/lib/python3.7/site-packages/pennylane/_grad.py", line 96, in __call__
    grad_value, ans = self._get_grad_fn(args)(*args, **kwargs)
  File "/home/nathan/anaconda3/lib/python3.7/site-packages/autograd/wrap_util.py", line 20, in nary_f
    return unary_operator(unary_f, x, *nary_op_args, **nary_op_kwargs)
  File "/home/nathan/anaconda3/lib/python3.7/site-packages/pennylane/_grad.py", line 113, in _grad_with_forward
    vjp, ans = _make_vjp(fun, x)
  File "/home/nathan/anaconda3/lib/python3.7/site-packages/autograd/core.py", line 10, in make_vjp
    end_value, end_node =  trace(start_node, fun, x)
  File "/home/nathan/anaconda3/lib/python3.7/site-packages/autograd/tracer.py", line 10, in trace
    end_box = fun(start_box)
  File "/home/nathan/anaconda3/lib/python3.7/site-packages/autograd/wrap_util.py", line 15, in unary_f
    return fun(*subargs, **kwargs)
  File "/home/nathan/anaconda3/lib/python3.7/site-packages/pennylane/tape/qnode.py", line 521, in __call__
    res = self.qtape.execute(device=self.device)
  File "/home/nathan/anaconda3/lib/python3.7/site-packages/pennylane/tape/tapes/tape.py", line 1070, in execute
    return self._execute(params, device=device)
  File "/home/nathan/anaconda3/lib/python3.7/site-packages/pennylane/tape/tapes/tape.py", line 1101, in execute_device
    res = device.execute(self)
  File "/home/nathan/anaconda3/lib/python3.7/site-packages/pennylane/_qubit_device.py", line 204, in execute
    self.apply(circuit.operations, rotations=circuit.diagonalizing_gates, **kwargs)
  File "/home/nathan/anaconda3/lib/python3.7/site-packages/pennylane/devices/default_qubit.py", line 188, in apply
    self._state = self._apply_operation(self._state, operation)
  File "/home/nathan/anaconda3/lib/python3.7/site-packages/pennylane/devices/default_qubit.py", line 213, in _apply_operation
    matrix = self._get_unitary_matrix(operation)
  File "/home/nathan/anaconda3/lib/python3.7/site-packages/pennylane/devices/default_qubit_autograd.py", line 167, in _get_unitary_matrix
    return unitary.eigvals
  File "/home/nathan/anaconda3/lib/python3.7/site-packages/pennylane/operation.py", line 878, in eigvals
    return super().eigvals
  File "/home/nathan/anaconda3/lib/python3.7/site-packages/pennylane/operation.py", line 753, in eigvals
    op_eigvals = self._eigvals(*self.parameters)
  File "/home/nathan/anaconda3/lib/python3.7/site-packages/pennylane/ops/qubit.py", line 678, in _eigvals
    p = cmath.exp(-0.5j * theta)
TypeError: must be real number, not ArrayBox

```
