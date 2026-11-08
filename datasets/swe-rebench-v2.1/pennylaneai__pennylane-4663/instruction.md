[BUG] `qml.data.load()` fails when using 'full' parameter value
### Expected behavior

`qml.data.load('qspin',sysname='Heisenberg',periodicity='open',lattice='full',layout='2x2')`
Should return the Heisenberg dataset corresponding to the `open` periodicity, `rectangular` lattice, and `2x2` layout.

### Actual behavior

`qml.data.load('qspin',sysname='Heisenberg',periodicity='open',lattice='full',layout='2x2')`

Raises `ValueError: layout value of '2x2' is not available. Available values are ['1x16', '1x4', '1x8']`

### Additional information

_No response_

### Source code

```shell
qml.data.load('qspin',sysname='Heisenberg',periodicity='open',lattice='full',layout='1x4') # works

qml.data.load('qspin',sysname='Heisenberg',periodicity='open',lattice='full',layout='2x2') # fails
```


### Tracebacks

_No response_

### System information

```shell
Name: PennyLane
Version: 0.31.0.dev0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/XanaduAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: .venv/lib/python3.8/site-packages
Editable project location:
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, requests, rustworkx, scipy, semantic-version, toml
Required-by: PennyLane-Lightning

Platform info:           Linux-5.15.0-73-generic-x86_64-with-glibc2.29
Python version:          3.8.10
Numpy version:           1.23.5
Scipy version:           1.10.1
Installed devices:
- default.gaussian (PennyLane-0.31.0.dev0)
- default.mixed (PennyLane-0.31.0.dev0)
- default.qubit (PennyLane-0.31.0.dev0)
- default.qubit.autograd (PennyLane-0.31.0.dev0)
- default.qubit.jax (PennyLane-0.31.0.dev0)
- default.qubit.tf (PennyLane-0.31.0.dev0)
- default.qubit.torch (PennyLane-0.31.0.dev0)
- default.qutrit (PennyLane-0.31.0.dev0)
- null.qubit (PennyLane-0.31.0.dev0)
- lightning.qubit (PennyLane-Lightning-0.30.0)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.
