[BUG] First-order derivative with unshifted shift term in gradient recipe breaks `param_shift`
### Expected behavior

The gradient is computed correctly by `qml.gradient.param_shift` even when using an operation that contains an unshifted term in its first-order gradient rule, provided via `gradient_recipe`.

### Actual behavior

A custom operation with the gradient recipe containing the term `[coeff, 1, 0]` breaks `param_shift` (`qnode1` in the code below) unless all operations require such a term (`qnode2` in the code below)

### Additional information

[HIDDEN]

### Source code

```shell
dev = qml.device('default.mixed', wires=2)

class OP(qml.operation.Operation):
    num_wires = 1
    ndim_params = (0,)
    num_params = 1
    grad_method = "A"
    #the first term corresponds to the unshifted tape
    grad_recipe = ([[1, 1, 0], [-1, 0, 1]],)

    @staticmethod
    def compute_decomposition(x, wires):
        return [qml.RX(x, wires=wires)]

@qml.qnode(dev)
def qnode1(params):
    OP(params[0], wires=0)
    qml.RY(0.1, wires=0)
    qml.RZ(params[1], wires=0)
    return qml.expval(qml.PauliZ(0))

@qml.qnode(dev)
def qnode2(params):
    OP(params[0], wires=0)
    OP(params[1], wires=0)
    return qml.expval(qml.PauliZ(0))

params = np.array([0.2, 0.3])
qnode(params)
qml.gradients.param_shift(qnode)(params)
```


### Tracebacks

```shell
---------------------------------------------------------------------------
IndexError                                Traceback (most recent call last)
Input In [6], in <cell line: 27>()
     25 params = np.array([0.2, 0.3])
     26 qnode(params)
---> 27 qml.gradients.param_shift(qnode)(params)

File ~/venvs/xanadu3.10/lib/python3.10/site-packages/PennyLane-0.25.0.dev0-py3.10.egg/pennylane/gradients/gradient_transform.py:269, in gradient_transform.default_qnode_wrapper.<locals>.jacobian_wrapper(*args, **kwargs)
    262     warnings.warn(
    263         "Attempted to compute the gradient of a QNode with no trainable parameters. "
    264         "If this is unintended, please add trainable parameters in accordance with "
    265         "the chosen auto differentiation framework."
    266     )
    267     return ()
--> 269 qjac = _wrapper(*args, **kwargs)
    271 if not hybrid:
    272     return qjac

File ~/venvs/xanadu3.10/lib/python3.10/site-packages/PennyLane-0.25.0.dev0-py3.10.egg/pennylane/transforms/batch_transform.py:313, in batch_transform.default_qnode_wrapper.<locals>._wrapper(*args, **kwargs)
    300     gradient_fn = None
    302 res = qml.execute(
    303     tapes,
    304     device=qnode.device,
   (...)
    310     **execute_kwargs,
    311 )
--> 313 return processing_fn(res)

File ~/venvs/xanadu3.10/lib/python3.10/site-packages/PennyLane-0.25.0.dev0-py3.10.egg/pennylane/gradients/parameter_shift.py:271, in expval_param_shift.<locals>.processing_fn(results)
    267     g = qml.math.tensordot(res, qml.math.convert_like(gradient_coeffs[i], res), [[0], [0]])
    269     if unshifted_coeffs:
    270         # add on the unshifted term
--> 271         g = g + unshifted_coeffs[i] * r0
    273     grads.append(g)
    275 # The following is for backwards compatibility; currently,
    276 # the device stacks multiple measurement arrays, even if not the same
    277 # size, resulting in a ragged array.
    278 # In the future, we might want to change this so that only tuples
    279 # of arrays are returned.

IndexError: list index out of range
```


### System information

```shell
Name: PennyLane
Version: 0.25.0.dev0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/XanaduAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /home/david/venvs/xanadu3.10/lib/python3.10/site-packages/PennyLane-0.25.0.dev0-py3.10.egg
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, retworkx, scipy, semantic-version, toml
Required-by: PennyLane-Lightning

Platform info:           Linux-5.4.0-121-generic-x86_64-with-glibc2.31
Python version:          3.10.5
Numpy version:           1.23.1
Scipy version:           1.9.0rc2
Installed devices:
- lightning.qubit (PennyLane-Lightning-0.24.0)
- default.gaussian (PennyLane-0.25.0.dev0)
- default.mixed (PennyLane-0.25.0.dev0)
- default.qubit (PennyLane-0.25.0.dev0)
- default.qubit.autograd (PennyLane-0.25.0.dev0)
- default.qubit.jax (PennyLane-0.25.0.dev0)
- default.qubit.tf (PennyLane-0.25.0.dev0)
- default.qubit.torch (PennyLane-0.25.0.dev0)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.
