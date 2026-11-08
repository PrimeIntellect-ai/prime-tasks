[Bug] `PauliSentence.to_mat(wire_order)` cannot handle Identities with wires
```python
PauliSentence({PauliWord({}): 1.}).to_mat([0, 1])
```

```pycon
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
Cell In[4], line 1
----> 1 PauliSentence({PauliWord({}): 1.}).to_mat([0, 1])

File ~/Xanadu/pennylane/pennylane/pauli/pauli_arithmetic.py:876, in PauliSentence.to_mat(self, wire_order, format, buffer_size)
    864 mats_and_wires_gen = (
    865     (
    866         coeff * pw.to_mat(wire_order=_pw_wires(pw.wires), format=format),
   (...)
    869     for pw, coeff in self.items()
    870 )
    872 reduced_mat, result_wire_order = math.reduce_matrices(
    873     mats_and_wires_gen=mats_and_wires_gen, reduce_func=math.add
    874 )
--> 876 return math.expand_matrix(reduced_mat, result_wire_order, wire_order=wire_order)

File ~/Xanadu/pennylane/pennylane/math/matrix_manipulation.py:135, in expand_matrix(mat, wires, wire_order, sparse_format)
    131 # get a subset of `wire_order` values that contain all wire labels inside `wires` argument
    132 # e.g. wire_order = [0, 1, 2, 3, 4]; wires = [3, 0, 2]
    133 # --> subset_wire_order = [0, 1, 2, 3]; expanded_wires = [3, 0, 2, 1]
    134 wire_indices = [wire_order.index(wire) for wire in wires]
--> 135 subset_wire_order = wire_order[min(wire_indices) : max(wire_indices) + 1]
    136 wire_difference = list(set(subset_wire_order) - set(wires))
    137 expanded_wires = wires + wire_difference

ValueError: min() arg is an empty sequence
```
