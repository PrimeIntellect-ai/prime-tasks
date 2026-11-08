[BUG] Issues with custom devices and transforms
### Expected behavior

Transforms applied to QNodes should work the same, independently of which device was used to create the QNode.

### Actual behavior

Executing the code provided below reveals a number of issues. The output I am getting (for example with PL v0.34.0 - but older version back to 0.30 behave essentially the same) is:
```
<default.qubit device (wires=1) at 0x7fae91eb3f10>
0: ──X─┤  <Z>
-1.0 <class 'pennylane.numpy.tensor.tensor'>
0: ──Y──X─┤  <Z>
1.0 <class 'pennylane.numpy.tensor.tensor'>
MyDevice
Short name: my.device
Package: __main__
Plugin version: 0.1.0
Author: Christian Gogolin
Wires: 1
Shots: 1000
0: ──X─┤  <Z>
[-1.] <class 'pennylane.numpy.tensor.tensor'>
0: ──X─┤  <Z>
[1.] <class 'pennylane.numpy.tensor.tensor'>
```
As you can see, when executing the transformed qnode the device receives the correct gates and produces the correct output (up to an odd mismatch in the shape of the returned tensor).

But when drawing the transformed qnode the transform does not seem to have any effect.
To me this is very mysterious because the device is not even needed for drawing the circuit.

With 0.29.1 my code imports the old batch_transform and the transformed circuit is drawn correctly.

### Additional information

_No response_

### Source code

```shell
from typing import Callable, Sequence

import pennylane as qml
try:
    from pennylane.transforms import transform
except ImportError: # pennylane < 0.31
    from pennylane.transforms import batch_transform as transform

from pennylane.tape import QuantumTape

from pennylane import Device
from pennylane import numpy as np

class MyDevice(Device):
    author = "Christian Gogolin"
    pennylane_requires = ">=0.29.1"
    name = "MyDevice"
    short_name = "my.device"
    version = "0.1.0"

    def __init__(self, wires, *args, **kwargs):
        if wires != 1:
            raise NotImplementedError()
        self._state = None
        super().__init__(wires, *args, **kwargs)

    def apply(self, operation, wires, par):
        self._state = qml.matrix(getattr(qml, operation))(0) @ self._state

    def expval(self, observable, wires, par):
        return float(np.real(np.dot(self._state.conj().T, qml.matrix(qml.PauliZ)(0).dot(self._state))).item())

    @property
    def observables(self):
        return ["PauliZ"]

    @property
    def operations(self):
        return ["PauliX", "PauliY"]

    def reset(self):
        self._state = np.array([1., 0.])

for dev in [qml.device("default.qubit", wires=1), MyDevice(wires=1)]:

    @qml.qnode(dev)
    def qnode():
        qml.PauliX(0)
        return qml.expval(qml.PauliZ(0))

    @transform
    def prepend_y(tape: QuantumTape) -> (Sequence[QuantumTape], Callable):

        try:
            new_tape = type(tape)([qml.PauliY(0)] + tape.operations, tape.measurements, shots=tape.shots)
        except AttributeError: # pennylane < 0.31
            new_tape = type(tape)([qml.PauliY(0)] + tape.operations, tape.measurements)

        def postprocessing(results):
            return results[0]

        return [new_tape], postprocessing

    print(dev)
    print(qml.draw(qnode)())
    res = qnode()
    print(res, type(res))
    print(qml.draw(prepend_y(qnode))())
    res2 = prepend_y(qnode)()
    print(res2, type(res2))
```


### Tracebacks

_No response_

### System information

```shell
Python 3.9.16 | packaged by conda-forge | (main, Feb  1 2023, 21:39:03)
[GCC 11.3.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import pennylane as qml; qml.about()
Name: PennyLane
Version: 0.34.0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/PennyLaneAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /home/cvjjm/miniforge3/envs/hfak/lib/python3.9/site-packages
Editable project location: /home/cvjjm/src/covqcstack/hfak/pennylane
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, requests, rustworkx, scipy, semantic-version, toml, typing-extensions
Required-by: covvqetools, PennyLane-Lightning, pennylane-umz

Platform info:           Linux-5.15.133.1-microsoft-standard-WSL2-x86_64-with-glibc2.31
Python version:          3.9.16
Numpy version:           1.23.0
Scipy version:           1.10.0
Installed devices:
- default.gaussian (PennyLane-0.34.0)
- default.mixed (PennyLane-0.34.0)
- default.qubit (PennyLane-0.34.0)
- default.qubit.autograd (PennyLane-0.34.0)
- default.qubit.jax (PennyLane-0.34.0)
- default.qubit.legacy (PennyLane-0.34.0)
- default.qubit.tf (PennyLane-0.34.0)
- default.qubit.torch (PennyLane-0.34.0)
- default.qutrit (PennyLane-0.34.0)
- null.qubit (PennyLane-0.34.0)
- lightning.qubit (PennyLane-Lightning-0.34.0)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

- `qml.draw(qnode, ...)` and `qml.draw_mpl(qnode, ...)` are the public drawing entry points. When a QNode has transforms attached (for example through the `qml.transform` decorator), both must render the operations that result after those transforms have been applied, so a transform that inserts a gate (such as a Pauli-X) is visible in the drawn output.
- This behaviour must hold for any device used to create the QNode, including user-defined devices that subclass `qml.Device`, and it must hold both for the default drawing path and when `expansion_strategy="device"` is requested.
