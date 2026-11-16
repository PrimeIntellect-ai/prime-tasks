Drawing fails for (a) qubit-wise commuting observables, and (b) QNodes with no operations
Consider the following minimal example in which a QNode returns multiple qubit wise commuting obeservables:
```python
import networkx
import pennylane as qml

from pennylane import expval, PauliX, PauliY, PauliZ

dev = qml.device('default.qubit', wires=4)
@qml.qnode(dev)
def qnode(x, y):
    qml.RY(x, wires=0)
    qml.Hadamard(0)
    qml.RZ(y, wires=0)
    return [expval(PauliX(wires=[0]) @ PauliX(wires=[1]) @ PauliX(wires=[2])), expval(PauliX(wires=[0]) @ PauliZ(wires=[3]))]
    #return [expval(PauliX(wires=[0]) @ PauliX(wires=[1]) @ PauliX(wires=[2]))]
    #return [expval(PauliX(wires=[0]) @ PauliZ(wires=[3]))]

qnode(1., 2.)
print(qnode.draw())
```

Problem 1: While executing the circuit works, drawing it leads to the error
```python
.../pennylane/circuit_drawer/grid.py in __init__(self, raw_grid)
     47             self.raw_grid = np.array(raw_grid, dtype=object)
     48             if len(self.raw_grid.shape) != 2:
---> 49                 raise ValueError(
     50                     "The entered raw grid was not parsed as two-dimensional array: {}".format(
     51                         raw_grid

ValueError: The entered raw grid was not parsed as two-dimensional array: [[expval(PauliZ(wires=[0]) @ PauliZ(wires=[1]) @ PauliZ(wires=[2])), expval(PauliZ(wires=[0]) @ PauliZ(wires=[3]))], [expval(PauliZ(wires=[0]) @ PauliZ(wires=[1]) @ PauliZ(wires=[2]))], [expval(PauliZ(wires=[0]) @ PauliZ(wires=[1]) @ PauliZ(wires=[2]))], [expval(PauliZ(wires=[0]) @ PauliZ(wires=[3]))]]
```
Commenting out the active return line line of the QNode and instead uncommenting one of the other two shows that PennyLane can draw with both observables individually, but not with both.

Problem 2: Trying to draw a circuit with no Operations (and only a return statement) results in the error:
```python
.../pennylane/pennylane/circuit_drawer/grid.py in copy(self)
    177             Grid: A copy of the Grid
    178         """
--> 179         return Grid(self.raw_grid.copy())
    180
    181     def append_grid_by_layers(self, other_grid):

AttributeError: 'NoneType' object has no attribute 'copy'
```

It would be nice if instead
```python
import networkx
import pennylane as qml

from pennylane import expval, PauliX, PauliY, PauliZ

dev = qml.device('default.qubit', wires=4)
@qml.qnode(dev)
def qnode(x, y):
    return [expval(PauliX(wires=[0]) @ PauliX(wires=[1]) @ PauliX(wires=[2]))]

qnode(1., 2.)
print(qnode.draw())
```
would simply draw
```
 0: ────╭┤ ⟨X ⊗ X ⊗ X⟩
 1: ────├┤ ⟨X ⊗ X ⊗ X⟩
 2: ────╰┤ ⟨X ⊗ X ⊗ X⟩
```

### Additional contract requirements

- For the two-observable QNode in Problem 1, `qnode.draw()` must succeed and render both returned measurements with their corresponding observables and wires.
- For the QNode in Problem 1 with its second observable changed to `PauliX(wires=[0]) @ PauliX(wires=[3])`, `qnode.draw()` must succeed and render both returned measurements with their corresponding observables and wires.
