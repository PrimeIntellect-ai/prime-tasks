[BUG] Decomposition of QubitUnitary on two wires is incorrect
### Expected behavior

The `two_qubit_decomposition` is correrct.

### Actual behavior

It is, for the most part, but here's a random matrix that it fails on:

```python
import pennylane as qml
import numpy as np
from pennylane.ops.op_math.decompositions.unitary_decompositions import two_qubit_decomposition

U = np.array(
    [[-0.40836553 - 0.28850926j, 0.23864466 - 0.4393731j,
      0.02190401 + 0.06284322j, -0.23169726 - 0.66474606j],
     [-0.48865844 - 0.10589111j, 0.49770294 + 0.04787262j,
      -0.02177958 + 0.45019526j, -0.02632749 + 0.54420285j],
     [0.49276489 - 0.08475118j, 0.47943096 - 0.14193644j,
      0.51448332 - 0.17932317j, -0.42560958 + 0.14834623j],
     [0.42041002 - 0.27065738j, -0.31807806 - 0.38578018j,
      -0.03401683 + 0.70314565j, -0.00321586 + 0.06647341j]]
)

decomp = two_qubit_decomposition(U, wires=[0, 1])
matrix = qml.matrix(qml.tape.QuantumScript(decomp), wire_order=[0, 1])
```
```pycon
>>> qml.math.allclose(matrix, U, atol=1e-7)
False
```


### Additional information

This is an old bug coming back to haunt us. See https://github.com/PennyLaneAI/pennylane/issues/5308 and https://github.com/PennyLaneAI/pennylane/issues/7339

### Source code

```shell

```

### Tracebacks

```shell

```

### System information

```shell
Name: Pennylane
Version: 0.42.0.dev31
Summary: PennyLane is a cross-platform Python library for quantum computing, quantum machine learning, and quantum chemistry. Train a quantum computer the same way as a neural network.
Home-page:
Author:
Author-email:
License-Expression: Apache-2.0
Location: /Users/astral.cai/Workspace/pennylane
Requires: appdirs, autograd, autoray, cachetools, diastatic-malt, networkx, numpy, packaging, pennylane-lightning, requests, rustworkx, scipy, tomlkit, typing_extensions
Required-by: PennyLane_Lightning

Platform info:           macOS-15.5-arm64-arm-64bit
Python version:          3.10.14
Numpy version:           1.26.4
Scipy version:           1.15.3
Installed devices:
- default.clifford (Pennylane-0.42.0.dev31)
- default.gaussian (Pennylane-0.42.0.dev31)
- default.mixed (Pennylane-0.42.0.dev31)
- default.qubit (Pennylane-0.42.0.dev31)
- default.qutrit (Pennylane-0.42.0.dev31)
- default.qutrit.mixed (Pennylane-0.42.0.dev31)
- default.tensor (Pennylane-0.42.0.dev31)
- null.qubit (Pennylane-0.42.0.dev31)
- reference.qubit (Pennylane-0.42.0.dev31)
- lightning.qubit (PennyLane_Lightning-0.41.1)
```

### Existing GitHub issues

- [x] I have searched existing GitHub issues to make sure the issue does not already exist.
