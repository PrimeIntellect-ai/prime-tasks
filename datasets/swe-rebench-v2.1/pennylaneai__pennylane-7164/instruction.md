Drawing `PrepSelPrep` shoud be less verbose
### Feature details

`PrepSelPrep`'s LCU argument is interpreted as a parameter, resulting in a verbose drawing. The feature we'd like to have is a custom label method that treats the LCU variable as a single array, which is displayed below the tape drawing like for other arrays.

### Implementation

_No response_

### How important would you say this feature is?

1: Not important. Would be nice to have.

### Additional information

```python
import numpy as np
import pennylane as qml

k = 4
num_terms = 2**k
ops = list(qml.pauli.pauli_group(k))[:num_terms]
lcu = qml.dot(np.random.random(num_terms), ops)
@qml.qnode(qml.device("default.qubit"))
def node():
    qml.PrepSelPrep(lcu, control=range(k, 2*k))
    return qml.state()
```

```
>>> print(qml.draw(node)())
0: ─╭PrepSelPrep(0.68,0.54,0.51,0.15,0.74,0.50,0.62,0.24,0.95,0.41,0.52,0.99,0.98,0.79,0.27,0.75)─┤
1: ─├PrepSelPrep(0.68,0.54,0.51,0.15,0.74,0.50,0.62,0.24,0.95,0.41,0.52,0.99,0.98,0.79,0.27,0.75)─┤
2: ─├PrepSelPrep(0.68,0.54,0.51,0.15,0.74,0.50,0.62,0.24,0.95,0.41,0.52,0.99,0.98,0.79,0.27,0.75)─┤
3: ─├PrepSelPrep(0.68,0.54,0.51,0.15,0.74,0.50,0.62,0.24,0.95,0.41,0.52,0.99,0.98,0.79,0.27,0.75)─┤
4: ─├PrepSelPrep(0.68,0.54,0.51,0.15,0.74,0.50,0.62,0.24,0.95,0.41,0.52,0.99,0.98,0.79,0.27,0.75)─┤
5: ─├PrepSelPrep(0.68,0.54,0.51,0.15,0.74,0.50,0.62,0.24,0.95,0.41,0.52,0.99,0.98,0.79,0.27,0.75)─┤
6: ─├PrepSelPrep(0.68,0.54,0.51,0.15,0.74,0.50,0.62,0.24,0.95,0.41,0.52,0.99,0.98,0.79,0.27,0.75)─┤
7: ─╰PrepSelPrep(0.68,0.54,0.51,0.15,0.74,0.50,0.62,0.24,0.95,0.41,0.52,0.99,0.98,0.79,0.27,0.75)─┤
```
