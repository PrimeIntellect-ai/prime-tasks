[BUG] Adjoint and backpropagation differentiation gives different results for custom qml.Hermitian observables
### Expected behavior

A QML model with a custom `qml.Hermitian` observable should give the identical results when trained with either adjoint differentiation or backprop differentiation methods.

### Actual behavior

The two differentiation methods give different results:
* The backprop trained algorithm learns and produces the expected accuracy.
* The adjoint trained algorithm does not learn at all, final predictions for a binary data set are always 0.5.

Again, as per the documentation, the two algorithms should produce identical results.

### Additional information

Here is the output produced by training with backprop and adjoint, respectively.

[backprop_output.txt](https://github.com/PennyLaneAI/pennylane/files/8463642/backprop_output.txt)
[adjoint_output.txt](https://github.com/PennyLaneAI/pennylane/files/8463643/adjoint_output.txt)

If we change to a default observable (line 35-36 in the code below) such as PauliZ we observe that adjoint and backprop give identical results, as you can see below.

[adjoint_output_pauliZ.txt](https://github.com/PennyLaneAI/pennylane/files/8463662/adjoint_output_pauliZ.txt)
[backprop_output_pauliZ.txt](https://github.com/PennyLaneAI/pennylane/files/8463663/backprop_output_pauliZ.txt)

This issue was first discussed here: https://discuss.pennylane.ai/t/adjoint-and-backpropagation-differentiation-methods-give-different-results/1731 .

### Source code

```shell
# Minimal example that reproduces the issue for the backprop and adjoint discrepancy.
import torch.nn as nn
import numpy as np
from sklearn.datasets import make_moons
import matplotlib.pyplot as plt
import torch
import pennylane as qml
import sys
from time import perf_counter

class Model(nn.Module):
    def __init__(self, dev, diff_method="backprop"):
        super().__init__()

        self.cnet_in = self.get_cnet_in()
        self.qcircuit = qml.qnode(dev, interface="torch",
                                  diff_method=diff_method)(self.qnode)

        weight_shape = {"weights":(2,)}
        self.qlayer = qml.qnn.TorchLayer(self.qcircuit, weight_shape)

    def get_cnet_in(self):
        layers = [nn.Linear(2,16), nn.ReLU(True), nn.Linear(16,2), nn.Sigmoid()]
        return nn.Sequential(*layers)

    def qnode(self, inputs, weights):
        # Data encoding:
        for x in range(len(inputs)):
            qml.Hadamard(x)
            qml.RZ(2.0 * inputs[x], wires=x)
        # Trainable part:
        qml.CNOT(wires=[0,1])
        qml.RY(weights[0], wires=0)
        qml.RY(weights[1], wires=1)
        o = [[1], [0]] * np.conj([[1], [0]]).T
        return qml.expval(qml.Hermitian(o, wires=[0]))
        #return qml.expval(qml.PauliY(wires=0))

    def forward(self, x):
        x = self.cnet_in(x)
        x = self.qlayer(x)
        return x

def train(X, y, dev_name, diff_method):

    dev = qml.device(dev_name, wires=2, shots=None)
    model  = Model(dev, diff_method)

    # Train the model
    opt = torch.optim.Adam(model.parameters(), lr=0.01)
    loss = torch.nn.MSELoss()

    X = torch.tensor(X, requires_grad=False).float()
    y = torch.Tensor(y).float()

    batch_size = 5
    batches = 200 // batch_size

    data_loader = torch.utils.data.DataLoader(
        list(zip(X, y)), batch_size=batch_size, shuffle=True, drop_last=True
    )

    epochs = 20
    avg_loss = []
    for epoch in range(epochs):

        running_loss = 0
        x = 0

        for xs, ys in data_loader:
            opt.zero_grad()

            loss_evaluated = loss(model(xs), ys)
            loss_evaluated.backward()
            opt.step()
            #print('Weights:', model.state_dict()['qlayer.weights'])
            running_loss += loss_evaluated
        loss_value = running_loss / batches
        avg_loss.append(loss_value.detach().numpy())
        print("Average loss over epoch {}: {:.10f}".format(epoch + 1, loss_value))

    y_pred = model(X)
    print(y_pred)
    predictions = (y_pred >= 0.5).type(torch.uint8)
    correct = [1 if p == p_true else 0 for p, p_true in zip(predictions, y)]
    accuracy = sum(correct) / len(correct)
    print(f"Accuracy: {accuracy * 100}%")

    return avg_loss


if __name__ == "__main__":
    torch.manual_seed(42)
    np.random.seed(42)
    X, y = make_moons(200)
    begin_time = perf_counter()
    avg_loss = train(X, y, str(sys.argv[1]), str(sys.argv[2]))
    end_time = perf_counter()
    runtime = end_time-begin_time
    print(f'Runtime: {runtime:.2e} s or {(runtime/60):.2e} min.')
```


### Tracebacks

_No response_

### System information

```shell
WARNING: pip is being invoked by an old script wrapper. This will fail in a future version of pip.
Please see https://github.com/pypa/pip/issues/5599 for advice on fixing the underlying issue.
To avoid this problem you can invoke Python with '-m pip' instead of running pip directly.
Name: PennyLane
Version: 0.20.0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/XanaduAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /home/vabelis/anaconda3/envs/ae_qml_pnl/lib/python3.8/site-packages
Requires: scipy, semantic-version, autograd, autoray, appdirs, pennylane-lightning, toml, numpy, cachetools, networkx
Required-by: PennyLane-qiskit, PennyLane-Lightning
Platform info:           Linux-3.10.0-1160.36.2.el7.x86_64-x86_64-with-glibc2.17
Python version:          3.8.12
Numpy version:           1.22.2
Scipy version:           1.7.3
Installed devices:
- default.gaussian (PennyLane-0.20.0)
- default.mixed (PennyLane-0.20.0)
- default.qubit (PennyLane-0.20.0)
- default.qubit.autograd (PennyLane-0.20.0)
- default.qubit.jax (PennyLane-0.20.0)
- default.qubit.tf (PennyLane-0.20.0)
- default.qubit.torch (PennyLane-0.20.0)
- qiskit.aer (PennyLane-qiskit-0.21.0)
- qiskit.basicaer (PennyLane-qiskit-0.21.0)
- qiskit.ibmq (PennyLane-qiskit-0.21.0)
- qiskit.ibmq.circuit_runner (PennyLane-qiskit-0.21.0)
- qiskit.ibmq.sampler (PennyLane-qiskit-0.21.0)
- lightning.qubit (PennyLane-Lightning-0.22.1)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

- When adjoint differentiation is asked to differentiate with respect to input parameters of `qml.Hermitian`, it must emit a `UserWarning` containing `Differentiating with respect to the input parameters of Hermitian`.
