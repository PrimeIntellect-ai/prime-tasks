[BUG] `sum` not working with hardware Hamiltonians (transmons and rydberg)
### Expected behavior

Working with hardware Hamiltonians, we add them together with similar syntax to `H = H_interaction + H_drive`. Often, we repeatedly add terms manually, e.g., `H_drive += qml.pulse.transmon_drive(amplitude, phase, freq, wires)`.

I would expect to be able to use `sum()` on a list of terms, such as:
`H_drive = sum([qml.pulse.transmon_drive(amplitude, phase, freq, q) for q in wires])`
Similar to how we can add other operators in PennyLane `sum([qml.PauliX(i) for i in range(wires)])`.

### Actual behavior

We can't do it.

### Additional information

I have tested this with a few `HardwareHamiltonian` instances using `qml.pulse.transmon_interaction`, `qml.pulse.transmon_drive`, `qml.pulse.rydberg_interaction` and `qml.pulse.rydberg_drive`.

We can manipulate all of them with stuff such as:
```python
H = qml.pulse.transmon_interaction(qubit_freqs, connection, couplings, wires)
for q in wires:
    H += qml.pulse.transmon_drive(amplitude, phase, freq, q)
```
Or even:
```python
H_int = qml.pulse.transmon_interaction(qubit_freqs, connection, couplings, wires)
drive_terms = [qml.pulse.transmon_drive(amplitude, phase, freq, q) for q in range(2)]
H_drive = drive_terms[0] + drive_terms[1]
H = H_int + H_drive
```

But we wouldn't be able to use `sum()` on any iterable containing `HardwareHamiltonian`s. I also tried changing the input types, e.g., setting `amplitude`, `phase`, and `freq` to be all callables, floats, or ints, or a combination of those.

### Source code

```shell
import pennylane as qml
sum([qml.pulse.transmon_drive(0., 0., 0., q) for q in range(2)])
```


### Tracebacks

```shell
---------------------------------------------------------------------------
TypeError                                 Traceback (most recent call last)
Cell In[1], line 2
      1 import pennylane as qml
----> 2 sum([qml.pulse.transmon_drive(0., 0., 0., q) for q in range(2)])

TypeError: unsupported operand type(s) for +: 'int' and 'HardwareHamiltonian'
```


### System information

```shell
Latest master

Name: PennyLane
Version: 0.32.0.dev0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/PennyLaneAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /home/borja.requena/.conda/envs/pl_dev/lib/python3.10/site-packages
Editable project location: /home/borja.requena/GitHub/pennylane
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, requests, rustworkx, scipy, semantic-version, toml
Required-by: PennyLane-Lightning

Platform info:           Linux-5.10.102.1-microsoft-standard-WSL2-x86_64-with-glibc2.31
Python version:          3.10.11
Numpy version:           1.23.5
Scipy version:           1.10.0
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
- lightning.qubit (PennyLane-Lightning-0.31.0)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.
