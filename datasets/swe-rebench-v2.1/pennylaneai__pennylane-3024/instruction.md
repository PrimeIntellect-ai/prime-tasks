[BUG] `single_qubit_fusion` returns wrong angles for specific case
### Expected behavior

The tape transform `single_qubit_fusion` always performs valid transforms, not changing the action of the tape.

### Actual behavior

For the following specific case, the transform reports wrong angles. Having tracked this down to `optimization_utils.fuse_rot_angles` already, I just report the minimal example here:
```pycon
>>> angles1 = [np.pi, np.pi/2, 0]
>>> angles2 = [0, -np.pi/2, 0]
>>> fuse_rot_angles(angles1, angles2)
array([0., 0., 0.])
```
As we can see, although only the `RY` rotation angles should cancel out, the `RZ` rotation caused by the first angle of `angles1` also disappeared.
As far as my experiments went, this bug seems to appear for a whole range of values, but I was not able to track down for which exactly. Tested examples include:
```pycon
#works
angles1 = [np.pi, np.pi/2, 0.]
angles2 = [0., -np.pi/2, 0.23]

#doesn't work
angles1 = [np.pi, np.pi/2, 0.]
angles2 = [0., -np.pi/2, 0.]

#works
angles1 = [np.pi, np.pi/2, 0.]
angles2 = [1., -np.pi/2, 0.3]

#doesn't work at all, produces `nan` angle
angles1 = [0.9, np.pi/2, 0.]
angles2 = [0., -np.pi/2, 0.]

#works
angles1 = [0.9, np.pi/2, 1.]
angles2 = [0., -np.pi/2, 0.]
```

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
Location: /home/david/venvs/xanadu3.10/lib/python3.10/site-packages/PennyLane-0.26.0.dev0-py3.10.egg
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, retworkx, scipy, semantic-version, toml
Required-by: amazon-braket-pennylane-plugin, PennyLane-Cirq, PennyLane-Lightning, PennyLane-PQ, PennyLane-qiskit, pennylane-qulacs

Platform info:           Linux-5.4.0-125-generic-x86_64-with-glibc2.31
Python version:          3.10.6
Numpy version:           1.23.1
Scipy version:           1.9.0rc2
Installed devices:
- braket.aws.qubit (amazon-braket-pennylane-plugin-1.6.9)
- braket.local.qubit (amazon-braket-pennylane-plugin-1.6.9)
- lightning.qubit (PennyLane-Lightning-0.25.0)
- projectq.classical (PennyLane-PQ-0.17.0)
- projectq.ibm (PennyLane-PQ-0.17.0)
- projectq.simulator (PennyLane-PQ-0.17.0)
- qulacs.simulator (pennylane-qulacs-0.13.0.dev0)
- cirq.mixedsimulator (PennyLane-Cirq-0.25.0.dev0)
- cirq.pasqal (PennyLane-Cirq-0.25.0.dev0)
- cirq.qsim (PennyLane-Cirq-0.25.0.dev0)
- cirq.qsimh (PennyLane-Cirq-0.25.0.dev0)
- cirq.simulator (PennyLane-Cirq-0.25.0.dev0)
- qiskit.aer (PennyLane-qiskit-0.25.0.dev0)
- qiskit.basicaer (PennyLane-qiskit-0.25.0.dev0)
- qiskit.ibmq (PennyLane-qiskit-0.25.0.dev0)
- qiskit.ibmq.circuit_runner (PennyLane-qiskit-0.25.0.dev0)
- qiskit.ibmq.sampler (PennyLane-qiskit-0.25.0.dev0)
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
