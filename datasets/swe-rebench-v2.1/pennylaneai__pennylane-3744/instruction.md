Parameter-shift rule of variance does not recycle unshifted evaluation
### Feature details

Save repeated evaluations at unshifted parameters when using `param_shift` together with gradient recipes that involve unshifted evaluations. Consider the setup
```python
import pennylane as qml
import numpy as np

dev = qml.device("default.qubit", wires=2)
x = [0.543, -0.654]

ops_with_custom_recipe = [0]

with qml.tape.QuantumTape() as tape:
    qml.RX(x[0], wires=[0])
    qml.RX(x[1], wires=[0])
    qml.var(qml.PauliZ(0))

gradient_recipes = tuple([[[-1e-7, 1, 0], [1e-7, 1, 0], [-1e5, 1, -5e-6], [1e5, 1, 5e-6]], None])
tapes, fn = qml.gradients.param_shift(tape, gradient_recipes=gradient_recipes)
```
Then we get:
```pycon
>>> for tape in tapes:
>>>     print(tape.get_parameters())
[0.543, -0.654]
[0.543, -0.654]
[0.542995, -0.654]
[0.5430050000000001, -0.654]
[0.543, 0.9167963267948965]
[0.543, -2.2247963267948965]
```
i.e. the unshifted tape is included twice, once for the unshifted evaluation in the product rule of the variance, and once for the shift rule that uses an unshifted term.


### Implementation

[HIDDEN]

### How important would you say this feature is?

1: Not important. Would be nice to have.

### Additional information

This issue occurs with and without the new return type system.

### Additional contract requirements

When a variance gradient and its gradient recipe both require evaluation at the original parameter values, the shared unshifted evaluation must be reused. The resulting gradient must remain mathematically correct. This behavior applies with and without the new return type system.
