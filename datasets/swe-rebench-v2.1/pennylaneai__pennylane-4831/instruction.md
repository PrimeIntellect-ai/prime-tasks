[BUG] Unexpected behavior with merge_amplitude_embedding and batched input
### Expected behavior

When using merge_amplitude_embedding to combine two separate embeddings, the output should be the same as two separate MottonenStatePreparations.

### Actual behavior

Instead, what I observe is that the output not only doesn't match the batch size, but it's also incorrect.


### Additional information

Removing `@qml.transforms.merge_amplitude_embedding` solves the issue, but I'm not sure it's intended.

### Source code

```shell
import pennylane as qml
import torch

dev = qml.device("default.qubit", wires=2)

@qml.qnode(dev, interface="torch")
def circuit1(a, b):
    qml.MottonenStatePreparation(a, wires=0)
    qml.MottonenStatePreparation(b, wires=1)
    return qml.probs(wires=range(2))

a = torch.randn((3,2))
b = torch.randn((3,2))
a = a/a.norm(dim=1, keepdim=True)
b = b/b.norm(dim=1, keepdim=True)

print('a:')
print(a)
print('b:')
print(b)

print('Batched call to circuit1')
print(circuit1(a, b).detach().numpy())

# Output:
# a:
# tensor([[ 0.4929,  0.8701],
#         [ 0.7628,  0.6466],
#         [-0.6488, -0.7610]])
# b:
# tensor([[-0.6827, -0.7307],
#         [ 0.6346, -0.7728],
#         [ 0.2947, -0.9556]])
# Batched call to circuit1
# [[0.11325859 0.12973125 0.35284562 0.40416454]
#  [0.23433313 0.34756744 0.16836992 0.24972952]
#  [0.03655629 0.38435813 0.0502934  0.52879218]]


@qml.transforms.merge_amplitude_embedding
@qml.qnode(dev, interface="torch")
def circuit2(a, b):
    qml.AmplitudeEmbedding(a, wires=0)
    qml.AmplitudeEmbedding(b, wires=1)
    return qml.probs(wires=range(2))

print('Batched call to circuit2')
print(circuit2(a, b).detach().numpy())

print('Repeated call to circuit2')
print(circuit2(a[0], b[0]).detach().numpy())
print(circuit2(a[1], b[1]).detach().numpy())
print(circuit2(a[2], b[2]).detach().numpy())


# Output:
# Batched call to circuit2
# [1. 0. 0. 0.]
# Repeated call to circuit2
# [1. 0. 0. 0.]
# [1. 0. 0. 0.]
# [1. 0. 0. 0.]
```


### Tracebacks

_No response_

### System information

```shell
Name: PennyLane
Version: 0.33.0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/PennyLaneAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /home/tiblias/miniconda3/envs/qc-gpu/lib/python3.10/site-packages
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, requests, rustworkx, scipy, semantic-version, toml, typing-extensions
Required-by: PennyLane-Lightning, PennyLane-Lightning-GPU, PennyLane-qiskit, pennylane-qulacs

Platform info:           Linux-6.2.0-36-generic-x86_64-with-glibc2.35
Python version:          3.10.12
Numpy version:           1.23.5
Scipy version:           1.11.2
Installed devices:
- default.gaussian (PennyLane-0.33.0)
- default.mixed (PennyLane-0.33.0)
- default.qubit (PennyLane-0.33.0)
- default.qubit.autograd (PennyLane-0.33.0)
- default.qubit.jax (PennyLane-0.33.0)
- default.qubit.legacy (PennyLane-0.33.0)
- default.qubit.tf (PennyLane-0.33.0)
- default.qubit.torch (PennyLane-0.33.0)
- default.qutrit (PennyLane-0.33.0)
- null.qubit (PennyLane-0.33.0)
- lightning.qubit (PennyLane-Lightning-0.33.1)
- lightning.gpu (PennyLane-Lightning-GPU-0.31.0)
- qiskit.aer (PennyLane-qiskit-0.31.0)
- qiskit.basicaer (PennyLane-qiskit-0.31.0)
- qiskit.ibmq (PennyLane-qiskit-0.31.0)
- qiskit.ibmq.circuit_runner (PennyLane-qiskit-0.31.0)
- qiskit.ibmq.sampler (PennyLane-qiskit-0.31.0)
- qiskit.remote (PennyLane-qiskit-0.31.0)
- qulacs.simulator (pennylane-qulacs-0.29.0)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.
