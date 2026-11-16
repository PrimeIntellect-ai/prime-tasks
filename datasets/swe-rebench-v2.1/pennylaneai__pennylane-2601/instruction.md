int to qml.BasisEmbedding
### Feature details

Currently, to use `BasisEmbedding` we have to pass a list with the bits [0,1,0,0] for example to put a PauliX gate in the second qubit. It would be nice to be able to pass an integer number like:

```python
qml.BasisEmbedding(4, wires = range(4))
```
This result would be the same that:

```python
qml.BasisEmbedding([0,1,0,0], wires = range(4))
```
because 0100 is the number 4 in binary (note that PennyLane uses the convention $|q_0,q_1,\dots,q_{N-1}\rangle$ where $q_0$ is the most significant bit).

This feature have a lot of applications, for example for qRAMs where we could do things like this one:

```python
for i in range(16):
      qml.BasisEmbedding(i, wires = range(4))
     ### some stuff here
```

### Implementation

I'm using this functions to translate the integer to the list:

[HIDDEN]

```
list_d(4,5)
>>> [0,0,1,0,0]
```

Probably incorporating this routine will be enough. However, some checks should be added because if num > 2^n_wires, the code will fail.


### How important would you say this feature is?

1: Not important. Would be nice to have.

### Additional information

Make sure that the order of the list is the same as Pennylane.
There are places where it is written from top to bottom and vice versa.

### Additional contract requirements

An integer value of zero is valid and prepares the all-zero bit string padded to the number of wires.
