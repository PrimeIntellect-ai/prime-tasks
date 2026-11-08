[BUG] `qml.QNSPSAOptimizer` [HIDDEN] in source
### Expected behavior

Circuit that includes `qml.RandomLayers` and uses `qml.QNSPSAOptimizer` executes normally.

### Actual behavior

Execution raises `AdjointUndefinedError`. Other optimizers execute fine.

### Additional information

`qml.QNSPSAOptimizer` [HIDDEN], as spotted by @albi3ro

Bug discovered by [Lucas Tecot on the PennyLane Discussion Forum](https://discuss.pennylane.ai/t/basisstate-raises-adjoint-undefined-error/2160/8).

### Source code

```shell
import pennylane as qml
from pennylane import numpy as plnp

num_qubits = 2
dev = qml.device("default.qubit", wires=num_qubits)
@qml.qnode(dev)
def cost(params):
    qml.RandomLayers(weights=params, wires=range(num_qubits), seed=42)
    return qml.expval(qml.PauliZ(0) @ qml.PauliZ(1))

params = plnp.random.normal(0, plnp.pi, (2, 4))
opt = qml.QNSPSAOptimizer(stepsize=5e-2)
for i in range(51):
    params, loss = opt.step_and_cost(cost, params)
    if i % 10 == 0:
        print(f"Step {i}: cost = {loss:.4f}")
```


### Tracebacks

_No response_

### System information

```shell
(Not relevant here.)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.
