[BUG] fourier.qnode_spectrum() returns different results depending on how the generator of a gate is defined
### Expected behavior

The output of `fourier.qnode_spectrum()` should be the same for two QNodes that differ only in that the generator of one of the gates is defined in a different way, which however represents the same operator.

### Actual behavior

Strangely enough I get diffrent spectra depending on whether `generator(self)` returns a `pennylane.ops.op_math.linear_combination.LinearCombination` or a `pennylane.ops.op_math.sum.Sum` representing the same operator.

See below for a minimal non-working example, which for me produces the output:

```
orig_generator    <class 'pennylane.ops.op_math.linear_combination.LinearCombination'> 0.25 * (X(0) @ Y(1)) + -0.25 * (Y(0) @ X(1))
[[0.+0.j  0.+0.j  0.+0.j  0.+0.j ]
 [0.+0.j  0.+0.j  0.+0.5j 0.+0.j ]
 [0.+0.j  0.-0.5j 0.+0.j  0.+0.j ]
 [0.+0.j  0.+0.j  0.+0.j  0.+0.j ]]
patched_generator <class 'pennylane.ops.op_math.sum.Sum'> (-0.25 * Y(0)) @ X(1) + (0.25 * X(0)) @ Y(1)
[[0.+0.j  0.+0.j  0.+0.j  0.+0.j ]
 [0.+0.j  0.+0.j  0.+0.5j 0.+0.j ]
 [0.+0.j  0.-0.5j 0.+0.j  0.+0.j ]
 [0.+0.j  0.+0.j  0.+0.j  0.+0.j ]]
<class 'pennylane.ops.qubit.qchem_ops.SingleExcitation'>
{'params': {(0,): [-1.0, -0.5, 0.0, 0.5, 1.0]}}
<class '__main__.MySingleExcitation'>
{'params': {(0,): [-1.0, 0.0, 1.0]}}
```

### Additional information

This used to work with v0.35.1.

### Source code

```shell
from pennylane import numpy as np
import pennylane as qml

dev = qml.device("default.qubit", wires=2, shots=None)

class MySingleExcitation(qml.SingleExcitation):
    # the definition from qml.SingleExcitation is
    # def generator2(self):
    #     w1, w2 = self.wires
    #     return qml.Hamiltonian([0.25, -0.25], [qml.X(w1) @ qml.Y(w2), qml.Y(w1) @ qml.X(w2)])
    # which should be exactly the same as:
    def generator(self):
        w1, w2 = self.wires
        return -0.25 * qml.PauliY(w1) @ qml.PauliX(w2) + 0.25 * qml.PauliX(w1) @ qml.PauliY(w2)

orig_generator = qml.SingleExcitation(0.1, wires=range(2)).generator()
patched_generator = MySingleExcitation(0.1, wires=range(2)).generator()

print("orig_generator   ", type(orig_generator), orig_generator)
print(qml.matrix(orig_generator, wire_order=range(2)))
print("patched_generator", type(patched_generator), patched_generator)
print(qml.matrix(patched_generator, wire_order=range(2)))

# check that they are the same generator
assert np.allclose(
    qml.matrix(orig_generator, wire_order=range(2)),
    qml.matrix(patched_generator, wire_order=range(2)),
)

for gate in [qml.SingleExcitation, MySingleExcitation]:

    print(gate)

    @qml.qnode(dev)
    def qnode(params):

        qml.PauliX(wires=0)
        qml.PauliX(wires=1)
        qml.OrbitalRotation(0.4, wires=range(4), id="OrbitalRotation")
        gate(params[0], wires=range(2), id="ReFermionEx")

        return qml.expval(qml.PauliZ(wires=0))

    params = np.array([0.1], requires_grad=True)
    spectrum_fn = qml.fourier.qnode_spectrum(qnode)
    spectra = spectrum_fn(params)
    print(spectra)
```

### Tracebacks

```shell

```

### System information

```shell
code was run with v0.40.0 I will provide this later.
```

### Existing GitHub issues

- [x] I have searched existing GitHub issues to make sure the issue does not already exist.
