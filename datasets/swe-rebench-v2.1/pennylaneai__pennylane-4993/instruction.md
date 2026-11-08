[BUG] qubit device expval method doesn't work with batch and BasisStateProjector
### Expected behavior

When utilizing a qubit device with batch processing, expval output, and BasisStateProjector, the probabilities need to be correctly indexed in the good dimension.

### Actual behavior

When utilizing a qubit device with batch processing, expval output, and BasisStateProjector, the probabilities are incorrectly index in the wrong dimension. This result in the expval output returning the probabilities of a vector within the batch, rather than providing the probabilities of the desired state for all entries in the batch.

### Additional information

A PR is already open for this issue. See https://github.com/PennyLaneAI/pennylane/pull/4971 .

### Source code

```shell
import pennylane as qml
from pennylane.devices import DefaultQubit
from pennylane.ops.qubit.observables import BasisStateProjector
import numpy as np


def circuit(x, y):
    n_wires = qml.math.shape(x)[-1]
    for i in range(n_wires):
        qml.RX(x[:, i], wires=i)
        qml.RY(y[:, i], wires=i)
    projector: BasisStateProjector = qml.Projector(np.zeros(n_wires), wires=range(n_wires))
    return qml.expval(projector)


if __name__ == '__main__':
    device = DefaultQubit(wires=2)
    qnode = qml.QNode(circuit, device)
    batch_size = device.num_wires * 3 + 1
    x = np.random.uniform(0, 2 * np.pi, size=(batch_size, device.num_wires))
    y = np.random.uniform(0, 2 * np.pi, size=(batch_size, device.num_wires))
    out = qnode(x, y)
    np.testing.assert_allclose(qml.math.shape(out), (batch_size,))
```


### Tracebacks

```shell
Traceback (most recent call last):
  File "E:\Github\FermionicSimulation\scratches\pennylane_pr.py", line 23, in <module>
    np.testing.assert_allclose(qml.math.shape(out), (batch_size,))
  File "E:\Github\FermionicSimulation\venv\lib\site-packages\numpy\testing\_private\utils.py", line 1527, in assert_allclose
    assert_array_compare(compare, actual, desired, err_msg=str(err_msg),
  File "E:\Github\FermionicSimulation\venv\lib\site-packages\numpy\testing\_private\utils.py", line 844, in assert_array_compare
    raise AssertionError(msg)
AssertionError:
Not equal to tolerance rtol=1e-07, atol=0

Mismatched elements: 1 / 1 (100%)
Max absolute difference: 3
Max relative difference: 0.42857143
 x: array([4])
 y: array([7])
```


### System information

```shell
Name: PennyLane
Version: 0.32.0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/PennyLaneAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: e:\github\fermionicsimulation\venv\lib\site-packages
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, requests, rustworkx, scipy, semantic-version, toml, typing-extensions
Required-by: PennyLane-Lightning

Platform info:           Windows-10-10.0.22621-SP0
Python version:          3.9.12
Numpy version:           1.23.5
Scipy version:           1.11.3
Installed devices:
- default.gaussian (PennyLane-0.32.0)
- default.mixed (PennyLane-0.32.0)
- default.qubit (PennyLane-0.32.0)
- default.qubit.autograd (PennyLane-0.32.0)
- default.qubit.jax (PennyLane-0.32.0)
- default.qubit.tf (PennyLane-0.32.0)
- default.qubit.torch (PennyLane-0.32.0)
- default.qutrit (PennyLane-0.32.0)
- null.qubit (PennyLane-0.32.0)
- lightning.qubit (PennyLane-Lightning-0.32.0)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

For a qubit device evaluating an expectation value of a basis-state projector on batched circuit inputs, the result contains the projected-state probability for each batch entry. This applies to projectors acting on multiple wires as well as one wire.
