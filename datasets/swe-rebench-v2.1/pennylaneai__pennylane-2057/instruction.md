Incorrect value of gradients at 0 after taking gradient twice
#### Issue description

A colleague noticed that when running `qml.grad` twice on a particular circuit, to compute a second derivative, the output value of the gradient is incorrect when the input value is precisely 0. The specific circuit is effectively the function `cos(x)` (see below for the code to reproduce).

* *Expected behavior:* The value of the second gradient at 0 for this function should be -1.

* *Actual behavior:* The value of the second gradient at 0 is computed to be -0.5.

* *Reproduces how often:* Always

* *System information:* (post the output of `import pennylane as qml; qml.about()`)

```
Name: PennyLane
Version: 0.15.0.dev0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/XanaduAI/pennylane
Author: None
Author-email: None
License: Apache License 2.0
Location: /home/olivia/Software/anaconda3/envs/xanadu/lib/python3.8/site-packages
Requires: appdirs, networkx, scipy, autograd, toml, semantic-version, numpy
Required-by: PennyLane-SF, pennylane-qulacs, PennyLane-qsharp, PennyLane-qiskit, PennyLane-Qchem, PennyLane-Forest, PennyLane-Cirq
Platform info:           Linux-5.4.0-66-generic-x86_64-with-glibc2.10
Python version:          3.8.5
Numpy version:           1.18.5
Scipy version:           1.4.1
Installed devices:
- default.gaussian (PennyLane-0.15.0.dev0)
- default.mixed (PennyLane-0.15.0.dev0)
- default.qubit (PennyLane-0.15.0.dev0)
- default.qubit.autograd (PennyLane-0.15.0.dev0)
- default.qubit.jax (PennyLane-0.15.0.dev0)
- default.qubit.tf (PennyLane-0.15.0.dev0)
- default.tensor (PennyLane-0.15.0.dev0)
- default.tensor.tf (PennyLane-0.15.0.dev0)
- strawberryfields.fock (PennyLane-SF-0.13.0.dev0)
- strawberryfields.gaussian (PennyLane-SF-0.13.0.dev0)
- strawberryfields.gbs (PennyLane-SF-0.13.0.dev0)
- strawberryfields.remote (PennyLane-SF-0.13.0.dev0)
- strawberryfields.tf (PennyLane-SF-0.13.0.dev0)
- qulacs.simulator (pennylane-qulacs-0.12.0)
- microsoft.QuantumSimulator (PennyLane-qsharp-0.8.0)
- qiskit.aer (PennyLane-qiskit-0.14.0.dev0)
- qiskit.basicaer (PennyLane-qiskit-0.14.0.dev0)
- qiskit.ibmq (PennyLane-qiskit-0.14.0.dev0)
- forest.numpy_wavefunction (PennyLane-Forest-0.13.0.dev0)
- forest.qpu (PennyLane-Forest-0.13.0.dev0)
- forest.qvm (PennyLane-Forest-0.13.0.dev0)
- forest.wavefunction (PennyLane-Forest-0.13.0.dev0)
- cirq.mixedsimulator (PennyLane-Cirq-0.13.0)
- cirq.pasqal (PennyLane-Cirq-0.13.0)
- cirq.qsim (PennyLane-Cirq-0.13.0)
- cirq.qsimh (PennyLane-Cirq-0.13.0)
- cirq.simulator (PennyLane-Cirq-0.13.0)
```

#### Source code and tracebacks

Code to reproduce:

```
import pennylane as qml
from pennylane import numpy as np

dev = qml.device("default.qubit", wires=1)

# Produces function cos(x)
@qml.qnode(dev)
def circuit(x):
    qml.RY(x, wires=0)
    return qml.expval(qml.PauliZ(0))

gradcos  = qml.grad(circuit)  # -sin(x)
gradcos2 = qml.grad(gradcos)  # -cos(x)

print(gradcos2(0.)) # Should be -1, but outputs -0.5

```

The issue seems to be at 0 specifically, as evaluating the gradient at `1e-6` yields a result very close to -1.

I tried another example as well:
```
# Produces function -i*sin(x)
@qml.qnode(dev)
def circuit(x):
    qml.PauliX(wires=0)
    qml.RX(x, wires=0)
    return qml.expval(qml.PauliZ(0))

gradcos  = qml.grad(circuit)  # -i * cos(x)
gradcos2 = qml.grad(gradcos)  # i * sin(x)

print(gradcos2(0.)) # Should be 1, but outputs 0.5
```
