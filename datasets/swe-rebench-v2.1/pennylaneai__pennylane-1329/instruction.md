[unitaryhack] Define decomposition for `qml.SWAP`
*This issue has been tagged for contributions during [unitaryHACK](https://unitaryfund.github.io/unitaryhack/participating-projects.html)*

Each PennyLane operation defines a decomposition. The decomposition of an operation is an ordered list of other operations. Applying this list of operations evolves quantum states the same way as applying the operation itself does. In most cases, this list includes elementary gates that are often supported by most quantum devices.

We would like to add the decomposition of the `qml.SWAP` operation by:
1. Defining the decomposition method for [the `qml.SWAP` operation](https://github.com/PennyLaneAI/pennylane/blob/1930230dde60112ad90af0951fa9295d374e1adf/pennylane/ops/qubit.py#L528) that has the following signature:
```python
    @staticmethod
    def decomposition(wires):
```
Other operations in the `pennylane/ops/qubit.py` file can serve as an example for defining this method (e.g., [see `qml.Hadamard`](https://github.com/PennyLaneAI/pennylane/blob/1930230dde60112ad90af0951fa9295d374e1adf/pennylane/ops/qubit.py#L87)).
2. Including a test case for the decomposition of `qml.SWAP` in the `tests/ops/test_qubit_ops.py` file to verify its correctness.
