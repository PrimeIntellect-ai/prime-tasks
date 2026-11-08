[BUG] pennylane.tape.Unwarp does not unwrap Hamiltonian coefficients
### Expected behavior

`qml.tape.unwrap` convert all ArrayBox in a tape to usual arrays.

### Actual behavior

Coefficients of the `Hamiltonian` object instance (accessible via `ham.coeffs`) are not unwrapped.

### Additional information

_No response_

### Source code

_No response_

### Tracebacks

_No response_

### System information

```shell
Name: PennyLane
Version: 0.26.0.dev0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/XanaduAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /home/chae-yeun/work/Xanadu/devel-py39/lib/python3.9/site-packages
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, retworkx, scipy, semantic-version, toml
Required-by: PennyLane-Lightning

Platform info:           Linux-5.14.0-1042-oem-x86_64-with-glibc2.35
Python version:          3.9.13
Numpy version:           1.23.2
Scipy version:           1.9.0
Installed devices:
- lightning.qubit (PennyLane-Lightning-0.26.0.dev1)
- default.gaussian (PennyLane-0.26.0.dev0)
- default.mixed (PennyLane-0.26.0.dev0)
- default.qubit (PennyLane-0.26.0.dev0)
- default.qubit.autograd (PennyLane-0.26.0.dev0)
- default.qubit.jax (PennyLane-0.26.0.dev0)
- default.qubit.tf (PennyLane-0.26.0.dev0)
- default.qubit.torch (PennyLane-0.26.0.dev0)
- default.qutrit (PennyLane-0.26.0.dev0)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

- The public entry point for this behaviour in the current code base is `qml.transforms.convert_to_numpy_parameters(tape)`. It returns a tape in which every `ArrayBox` value is converted to a usual NumPy array, including the coefficients of a `Hamiltonian` observable (accessible via `Hamiltonian.coeffs` and `Hamiltonian.data`).
