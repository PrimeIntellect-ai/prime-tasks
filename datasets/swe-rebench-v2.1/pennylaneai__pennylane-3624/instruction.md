[BUG] qml.chem.molecular_hamiltonian sets random number generator seed
### Expected behavior

When using the argument `shots=100`  to a device one expects variation in the output. This variation depends on the random number generator that is used internally in the device.

Setting on controlling the seed of the RNG is not possible at this moment, see https://github.com/PennyLaneAI/pennylane/issues/1327

In an application with a for loop over some parameters of the system the results of a circuit turned out to be always the same (instead of a random variation due to the finite number of shots). The problem turns out to be in a call to `qml.qchem.molecular_hamiltonian` which seems to reset the RNG. A minimal example:

```
import pennylane
import pennylane as qml
from pennylane import numpy as np
symbols = ["H", "H"]
coordinates = np.array([0.0, 0.0, -0.6614, 0.0, 0.0, 0.6614])
H, qubits = qml.qchem.molecular_hamiltonian(symbols, coordinates)
dev = qml.device("default.qubit", wires=qubits, shots=100)

@qml.qnode(dev)
def F():
    qml.BasisState(np.array([0,0,0,0]), wires=[0,1,2,3])
    qml.Hadamard(0)
    qml.Hadamard(1)

    return qml.expval(H)

#%% Circuit has variation in the result, as expected for a finite number of shots

[F() for ii in range(10)]

#%% Redefining the device does not lead to reproducible results. How can we set the seed?

for ii in range(10):
    dev = qml.device("default.qubit", wires=qubits, shots=100)

    @qml.qnode(dev)
    def F():
        qml.BasisState(np.array([0,0]), wires=[0,1])
        qml.Hadamard(0)
        qml.Hadamard(1)
        return qml.expval(H)
    print(F())


#%% Making a call to qml.qchem.molecular_hamiltonian seems to reset the seed
for ii in range(10):
    dev = qml.device("default.qubit", wires=qubits, shots=100)
    H, qubits = qml.qchem.molecular_hamiltonian(symbols, coordinates)

    @qml.qnode(dev)
    def F():
        qml.BasisState(np.array([0,0,0,0]), wires=[0,1,2,3])
        qml.Hadamard(0)
        qml.Hadamard(1)
        return qml.expval(H)
    print(F())

#%% Check the call indeed modifies the seed:

qml.qchem.molecular_hamiltonian(symbols, coordinates)
s1=np.random.get_state()
np.random.rand()
qml.qchem.molecular_hamiltonian(symbols, coordinates)
s2=np.random.get_state()

print(s1)
print(s2)
```

Expected behaviour:

* `qml.qchem.molecular_hamiltonian` should not modify the RNG seed




### Actual behavior

`qml.qchem.molecular_hamiltonian` changes the RNG seed


### Additional information

_No response_

### Source code

_No response_

### Tracebacks

_No response_

### System information

```shell
Name: PennyLane
Version: 0.28.0.dev0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/XanaduAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: c:\develop\env310\lib\site-packages
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, requests, retworkx, scipy, semantic-version, toml
Required-by: PennyLane-Lightning

Platform info:           Windows-10-10.0.19045-SP0
Python version:          3.10.8
Numpy version:           1.24.1
Scipy version:           1.9.2
Installed devices:
- default.gaussian (PennyLane-0.28.0.dev0)
- default.mixed (PennyLane-0.28.0.dev0)
- default.qubit (PennyLane-0.28.0.dev0)
- default.qubit.autograd (PennyLane-0.28.0.dev0)
- default.qubit.jax (PennyLane-0.28.0.dev0)
- default.qubit.tf (PennyLane-0.28.0.dev0)
- default.qubit.torch (PennyLane-0.28.0.dev0)
- default.qutrit (PennyLane-0.28.0.dev0)
- null.qubit (PennyLane-0.28.0.dev0)
- lightning.qubit (PennyLane-Lightning-0.26.1)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.
