Noise channels do not validate parameter values, leading to errors
#### Issue description

Description of the issue - include code snippets and screenshots here
if relevant. You may use the following template below

* *Expected behavior:* Raise an error showing that the probability (or sum of probabilities) are not compatible with the expected channel behaviour.

* *Actual behavior:* Raises a `RuntimeWarning` for an invalid value encountered in sqrt.

* *Reproduces how often:* 100%

* *System information:*
* Name: PennyLane
Version: 0.16.0.dev0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/XanaduAI/pennylane
Author: None
Author-email: None
License: Apache License 2.0
Location: /home/nahum/Documents/pennylane-training/pen-env/lib/python3.6/site-packages
Requires: scipy, toml, appdirs, autoray, semantic-version, networkx, autograd, numpy
Required-by: PennyLane-qiskit
Platform info:           Linux-5.4.0-73-generic-x86_64-with-debian-buster-sid
Python version:          3.6.8
Numpy version:           1.19.5
Scipy version:           1.5.4
Installed devices:
- default.gaussian (PennyLane-0.16.0.dev0)
- default.mixed (PennyLane-0.16.0.dev0)
- default.qubit (PennyLane-0.16.0.dev0)
- default.qubit.autograd (PennyLane-0.16.0.dev0)
- default.qubit.jax (PennyLane-0.16.0.dev0)
- default.qubit.tf (PennyLane-0.16.0.dev0)
- default.tensor (PennyLane-0.16.0.dev0)
- default.tensor.tf (PennyLane-0.16.0.dev0)
- qiskit.aer (PennyLane-qiskit-0.15.0)
- qiskit.basicaer (PennyLane-qiskit-0.15.0)
- qiskit.ibmq (PennyLane-qiskit-0.15.0)

#### Source code and tracebacks
```python
from pennylane.ops.channel import AmplitudeDamping

print(AmplitudeDamping(2, wires=0).kraus_matrices)
```

```
pennylane/ops/channel.py:61: RuntimeWarning: invalid value encountered in sqrt
  K0 = np.diag([1, np.sqrt(1 - gamma)])
[array([[ 1.,  0.],
       [ 0., nan]]), array([[0.        , 1.41421356],
       [0.        , 0.        ]])]
```
