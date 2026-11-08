Implement labels for broadcasted operators
### Feature details

When using parameter broadcasting and creating the label of an operation, its data is perceived as a matrix by PennyLane and therefore represented only symbolically:
```pycon
>>> @qml.qnode(dev)
>>> def qnode(x):
>>>     qml.RY(x, 0)
>>>     return qml.expval(qml.PauliZ(0))
>>> qml.draw(qnode)(np.array(0.5))
'0: ──RY(0.50)─┤  <Z>'
>>> qml.draw(qnode)(np.array([0.5, 0.9]))
'0: ──RY(M0)─┤  <Z>'
```
For large broadcasting dimensions this is definitely reasonable, as otherwise large arrays would be printed in circuit drawings, cluttering the drawing. However, for small broadcasting dimensions, like the two shifts of Pauli rotation parameter-shift rules, it would be useful to print out the broadcasted parameters explicitly.

### Implementation

One could
1. Decide for a cut-off size of the broadcasting axis and "simply" implement parameter printing for smaller data and symbolic printing (like `M0` above) for larger data; or
2. as tapes with broadcasted parameters have a unique `batch_size`, one could print out _multiple_ tapes, one for each value of the broadcasted parameter(s) (and the other ones being constant, of course). Again, there probably should be an upper limit as to how many tapes are drawn at most.

### How important would you say this feature is?

1: Not important. Would be nice to have.

### Additional information

The priority of this is lowered due to broadcasting being used mostly internally until now.

### Additional contract requirements

- When an operation has a broadcasted (array-valued) parameter, drawing the circuit must make the
  broadcasted parameter values visible instead of leaving them only as a symbolic matrix label.
  With the default `show_matrices=True`, the operation label uses a symbolic matrix name (for
  example `M0`) and the matrix of broadcasted values is printed below the diagram.
