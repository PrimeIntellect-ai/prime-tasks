[BUG] Split non commuting fails with lightning.kokkos
### Expected behavior

Split non commuting works for lightning kokkos

### Actual behavior

An exception is thrown.

### Additional information

Not an urgent bug, just looking at some tests I have for catalyst transforms.

### Source code

```shell
import jax
import pennylane as qml
import pennylane.transforms

def test_split_non_commuting():
    @qml.transforms.split_non_commuting
    @qml.qnode(qml.device("lightning.kokkos", wires=6), interface="jax")
    def interpreted():
        qml.Hadamard(1)
        qml.Hadamard(0)
        qml.PauliZ(0)
        qml.Hadamard(3)
        qml.Hadamard(5)
        qml.T(5)
        return (
            qml.expval(qml.PauliZ(0) @ qml.PauliZ(1)),
            qml.expval(qml.PauliX(0)),
            qml.expval(qml.PauliZ(1)),
            qml.expval(qml.PauliX(1) @ qml.PauliX(4)),
            qml.expval(qml.PauliX(3)),
            qml.expval(qml.PauliY(5)),
        )

    interpreted()

test_split_non_commuting()
```


### Tracebacks

```shell
python bug.py
Kokkos::OpenMP::initialize WARNING: OMP_PROC_BIND environment variable not set
  In general, for best performance with OpenMP 4.0 or better set OMP_PROC_BIND=spread and OMP_PLACES=threads
  For best performance with OpenMP 3.1 set OMP_PROC_BIND=true
  For unit testing set OMP_PROC_BIND=false

Traceback (most recent call last):
  File "/home/erick.ochoalopez/Code/cataliist/bug.py", line 26, in <module>
    test_split_non_commuting()
  File "/home/erick.ochoalopez/Code/cataliist/bug.py", line 8, in test_split_non_commuting
    def interpreted():
  File "/home/erick.ochoalopez/Code/env/lib/python3.10/site-packages/pennylane/transforms/core/transform_dispatcher.py", line 96, in __call__
    return self._qnode_transform(obj, targs, tkwargs)
  File "/home/erick.ochoalopez/Code/env/lib/python3.10/site-packages/pennylane/transforms/core/transform_dispatcher.py", line 208, in default_qnode_transform
    [HIDDEN]
  File "/home/erick.ochoalopez/.pyenv/versions/3.10.11/lib/python3.10/copy.py", line 172, in deepcopy
    y = _reconstruct(x, memo, *rv)
  File "/home/erick.ochoalopez/.pyenv/versions/3.10.11/lib/python3.10/copy.py", line 271, in _reconstruct
    state = deepcopy(state, memo)
  File "/home/erick.ochoalopez/.pyenv/versions/3.10.11/lib/python3.10/copy.py", line 146, in deepcopy
    y = copier(x, memo)
  File "/home/erick.ochoalopez/.pyenv/versions/3.10.11/lib/python3.10/copy.py", line 231, in _deepcopy_dict
    y[deepcopy(key, memo)] = deepcopy(value, memo)
  File "/home/erick.ochoalopez/.pyenv/versions/3.10.11/lib/python3.10/copy.py", line 172, in deepcopy
    y = _reconstruct(x, memo, *rv)
  File "/home/erick.ochoalopez/.pyenv/versions/3.10.11/lib/python3.10/copy.py", line 271, in _reconstruct
    state = deepcopy(state, memo)
  File "/home/erick.ochoalopez/.pyenv/versions/3.10.11/lib/python3.10/copy.py", line 146, in deepcopy
    y = copier(x, memo)
  File "/home/erick.ochoalopez/.pyenv/versions/3.10.11/lib/python3.10/copy.py", line 231, in _deepcopy_dict
    y[deepcopy(key, memo)] = deepcopy(value, memo)
  File "/home/erick.ochoalopez/.pyenv/versions/3.10.11/lib/python3.10/copy.py", line 161, in deepcopy
    rv = reductor(4)
TypeError: cannot pickle 'pennylane_lightning_kokkos.lightning_kokkos_qubit_ops.LightningKokkos_C128' object
```


### System information

```shell
Python 3.10.11 (main, May 13 2023, 12:07:51) [GCC 9.4.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import pennylane as qml
>>> qml.about()
Name: PennyLane
Version: 0.34.0.dev0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/PennyLaneAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /home/erick.ochoalopez/Code/env/lib/python3.10/site-packages
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, requests, rustworkx, scipy, semantic-version, toml, typing-extensions
Required-by: pennylane-catalyst, PennyLane-Lightning, PennyLane-Lightning-Kokkos

Platform info:           Linux-5.15.0-84-generic-x86_64-with-glibc2.31
Python version:          3.10.11
Numpy version:           1.26.1
Scipy version:           1.11.3
Installed devices:
- default.gaussian (PennyLane-0.34.0.dev0)
- default.mixed (PennyLane-0.34.0.dev0)
- default.qubit (PennyLane-0.34.0.dev0)
- default.qubit.autograd (PennyLane-0.34.0.dev0)
- default.qubit.jax (PennyLane-0.34.0.dev0)
- default.qubit.legacy (PennyLane-0.34.0.dev0)
- default.qubit.tf (PennyLane-0.34.0.dev0)
- default.qubit.torch (PennyLane-0.34.0.dev0)
- default.qutrit (PennyLane-0.34.0.dev0)
- null.qubit (PennyLane-0.34.0.dev0)
- lightning.kokkos (PennyLane-Lightning-Kokkos-0.32.0)
- lightning.qubit (PennyLane-Lightning-0.32.0)
>>>
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

- Applying a transform to a `QNode` must not copy the device: the transformed `QNode` keeps the same device object as the original, so the original device's tracker records executions run through the transformed circuit. This must hold for devices that cannot be deep-copied, such as `lightning.kokkos`.
- Shallow-copying a `QNode` (for example with `copy.copy`) must return a new `QNode` that shares the original's `func`, `device`, `interface`, `diff_method`, and `expansion_strategy`, while the copy has its own independent `execute_kwargs`, `gradient_kwargs`, and transform program.
